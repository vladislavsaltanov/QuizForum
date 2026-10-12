# Moodle-style tests: a combination of Questions that live only inside the test,
# answered all at once with one submit. Open or password-protected.
# Creation configures all questions inline and publishes everything at once;
# afterwards questions are managed one by one from the test edit page through
# the regular question form bound to the test.
class TestsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: %i[create update authenticate attempt],
             with: -> { redirect_back fallback_location: root_path, alert: "Попробуйте позже." }

  # Feed of tests, newest first.
  def index
    @tests = Test.order(created_at: :desc).includes(:author, :questions)
  end

  # Blank form with three empty question rows; blank rows are dropped on save.
  def new
    @test = Test.new(deadline: 7.days.from_now.change(sec: 0))
    @question_rows = 3.times.map { {} }
  end

  # Publishes the test with all its questions at once; blank password stays
  # NULL (open test). Questions are scoped to the test (deadline = test
  # deadline, no tags) and never appear on the feed.
  def create
    @test = Current.user.authored_tests.build(test_params)
    @test.questions = parse_questions(deadline: @test.deadline, author: Current.user)
    @test.questions.each { moderation_blocked?(_1) }
    @test.errors.add(:base, "Добавьте хотя бы один вопрос.") if @test.questions.empty?
    if @test.errors.empty? && @test.valid? && @test.questions.all?(&:valid?) && @test.save
      redirect_to @test, notice: "Тест опубликован."
    else
      @test.questions.each { |q| q.errors.each { |e| @test.errors.add(:base, "#{q.title.presence || 'Вопрос'}: #{e.full_message}") } }
      @question_rows = question_rows_from_params.presence || 3.times.map { {} }
      flash.now[:alert] = @test.errors.full_messages.to_sentence.presence || "Не удалось сохранить. Повторите."
      render :new, status: :unprocessable_entity
    end
  end

  # Manage page: test settings, question title list, per-question points.
  def edit
    @test = Test.includes(:questions).find(params[:id])
    return head(:forbidden) unless @test.editable_by?(Current.user)
    @questions = @test.questions.to_a
  end

  # Saves settings, per-question points, and re-syncs question deadlines.
  def update
    @test = Test.includes(:questions).find(params[:id])
    return head(:forbidden) unless @test.editable_by?(Current.user)
    @test.assign_attributes(test_params)
    points = params.fetch(:questions_points, {}).to_unsafe_h
    @test.questions.each do |q|
      q.points = points[q.id.to_s].to_i.clamp(0, 100) if points.key?(q.id.to_s)
    end
    if @test.valid? && @test.questions.all?(&:valid?)
      Test.transaction do
        @test.save!
        @test.questions.each(&:save!)
        @test.questions.update_all(deadline: @test.deadline)
      end
      redirect_to edit_test_path(@test), notice: "Тест обновлён."
    else
      @questions = @test.questions.to_a
      flash.now[:alert] = @test.errors.full_messages.to_sentence.presence || "Не удалось сохранить. Повторите."
      render :edit, status: :unprocessable_entity
    end
  end

  # All questions on one page, one submit for the whole test; scoreboard after deadline.
  def show
    @test = Test.includes(:author, questions: :attempts).find(params[:id])
    @questions = @test.questions.to_a
    return render_gate unless @test.unlocked?(Current.user, session)
    @my_attempts = Attempt.where(question: @questions, user: Current.user).index_by(&:question_id)
    @answered = @my_attempts.any?
    @scoreboard = build_scoreboard if @test.closed?
  end

  # Checks the test password and remembers it in the session.
  def authenticate
    @test = Test.find(params[:id])
    if @test.authenticate(params[:password].to_s)
      session[@test.unlock_key] = true
      redirect_to @test, notice: "Доступ открыт."
    else
      redirect_to @test, alert: "Неверный пароль."
    end
  end

  # Saves one attempt per question in a single transaction: answering the test
  # is a single indivisible attempt, never one question at a time.
  def attempt
    @test = Test.includes(:questions).find(params[:id])
    return render_gate(status: :forbidden) unless @test.unlocked?(Current.user, session)
    return redirect_to @test, alert: "Дедлайн прошёл." if @test.closed?
    return redirect_to @test, alert: "Вы уже ответили на этот тест." if @test.answered_by?(Current.user)
    records = @test.questions.map { |q| q.attempts.build(answer_params(q.id).merge(user: Current.user)) }
    unless records.all?(&:valid?)
      msg = records.flat_map { it.errors.full_messages }.to_sentence
      return redirect_to @test, alert: msg.presence || "Не удалось сохранить. Повторите."
    end
    Attempt.transaction do
      records.each(&:save!)
      records.each do |attempt|
        if attempt.question.code?
          AttemptCodeCheckJob.perform_later(attempt.id)
        elsif !attempt.question.choice?
          AttemptJuryJob.perform_later(attempt.id)
        end
      end
    end
    redirect_to @test, notice: "Попытка записана: все вопросы сразу."
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Double submit raced the unique user/question index; the savepoint undid all rows.
    redirect_to @test, alert: "Вы уже ответили на этот тест."
  end

  private
    # Password form instead of the test body; strangers never see questions.
    def render_gate(status: :ok)
      render :gate, status:
    end

    # Post-deadline totals per respondent from one preloaded relation.
    def build_scoreboard
      by_user = @test.questions.flat_map(&:attempts).group_by(&:user_id)
      users = User.where(id: by_user.keys).index_by(&:id)
      by_user.filter_map do |uid, attempts|
        user = users[uid]
        next unless user
        verdicts = attempts.index_by(&:question_id)
        total = @test.questions.sum { it.score_for(verdicts[it.id]&.verdict) }
        [ user, total ]
      end.sort_by { |u, total| [ -total, u.name ] }
    end

    # Whitelisted test form fields.
    def test_params
      params.expect(test: [ :title, :body, :deadline, :password, :max_points ])
    end

    # Zips parallel question form arrays into Question rows, skipping blank titles.
    # Options come one per line; a leading "*" marks the correct ones.
    def parse_questions(deadline:, author:)
      titles = Array(params[:questions_title])
      types = Array(params[:questions_answer_type])
      bodies = Array(params[:questions_body])
      references = Array(params[:questions_reference])
      opts = Array(params[:questions_options])
      points = Array(params[:questions_points])
      titles.each_with_index.filter_map do |title, i|
        title = title.to_s.strip
        next if title.empty?
        type = Question::ANSWER_TYPES.include?(types[i]) ? types[i] : "text"
        Question.new(title:, body: bodies[i].to_s.strip, answer_type: type,
          reference_answer: references[i].to_s.strip,
          options: parse_question_options(opts[i], type),
          points: points[i].to_i.clamp(0, 100), position: i,
          deadline:, author:, test: @test, tags: [])
      end
    end

    # One option per line; "*" prefix means correct. Only choice types keep options.
    def parse_question_options(raw, type)
      return [] unless type == "single_choice" || type == "multiple_choice"
      raw.to_s.lines.filter_map do |line|
        line = line.strip
        next if line.empty?
        correct = line.start_with?("*")
        { "text" => (correct ? line[1..].strip : line), "correct" => correct }
      end
    end

    # Same Laya bar as standalone questions; errors land on the question, not the test.
    def moderation_blocked?(question)
      moderation_text = AiQuestionIngest.moderation_text(
        title: question.title, body: question.body, tags: [],
        reference_answer: question.reference_answer, explanation: nil,
        example_input: nil, example_output: nil, options: question.options)
      verdict = ModerationClient.check(text: moderation_text)
      question.errors.add(:base, "Отклонено проверкой: #{verdict.category}.") if verdict.verdict == :reject
      question.errors.add(:base, "Проверка не удалась, попробуйте позже.") if verdict.verdict == :try_later
    end

    # Echo the submitted rows back into the form after a failed save.
    def question_rows_from_params
      titles = Array(params[:questions_title])
      return [] if titles.all?(&:blank?)
      titles.each_with_index.map do |title, i|
        { "title" => title, "answer_type" => Array(params[:questions_answer_type])[i],
          "body" => Array(params[:questions_body])[i],
          "reference" => Array(params[:questions_reference])[i],
          "points" => Array(params[:questions_points])[i],
          "options" => Array(params[:questions_options])[i] }
      end
    end

    # One question's answers from the combined form, keyed by question id.
    # Missing rows yield {} so the attempt fails validation, never 400.
    def answer_params(question_id)
      all = params[:answers]
      return {} unless all.is_a?(ActionController::Parameters)
      entry = all[question_id.to_s]
      return {} unless entry.is_a?(ActionController::Parameters)
      entry.permit(:body, :language, selected: []).to_h
    end
end
