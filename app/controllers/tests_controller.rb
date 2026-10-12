# Moodle-style tests: a combination of Questions that live only inside the test,
# answered all at once with one submit. Open or password-protected.
# Lifecycle: "Новый тест" opens a draft at once — settings, bare question
# title list and the add button share one creation screen; "Опубликовать"
# at the end makes it visible to everyone. Drafts die safely (no attempts).
class TestsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: %i[update authenticate attempt],
             with: -> { redirect_back fallback_location: root_path, alert: "Попробуйте позже." }

  # Feed of published tests plus the author's own drafts, newest first.
  def index
    @tests = Test.published.or(Test.where(author: Current.user)).order(created_at: :desc)
      .includes(:author, :questions)
  end

  # One creation screen: the draft opens immediately, so the question list
  # and the add button live on the same page as the settings.
  def new
    @test = Current.user.authored_tests.create!(title: "Новый тест", deadline: 7.days.from_now.change(sec: 0))
    @questions = []
    render :edit
  end

  # Creation screen for drafts, manage page for published: test settings,
  # bare question title list, per-question points.
  def edit
    @test = Test.includes(:questions).find(params[:id])
    return head(:forbidden) unless @test.editable_by?(Current.user)
    @questions = @test.questions.to_a
  end

  # Saves settings, per-question points, and re-syncs question deadlines.
  # With publish=1 a draft with at least one question goes public.
  def update
    @test = Test.includes(:questions).find(params[:id])
    return head(:forbidden) unless @test.editable_by?(Current.user)
    @test.assign_attributes(test_params)
    points = params.fetch(:questions_points, {}).to_unsafe_h
    @test.questions.each do |q|
      q.points = points[q.id.to_s].to_i.clamp(0, 100) if points.key?(q.id.to_s)
    end
    if params[:publish].present?
      @test.errors.add(:base, "Добавьте хотя бы один вопрос.") if @test.questions.empty?
      @test.published = true if @test.errors.empty?
    end
    if @test.errors.empty? && @test.valid? && @test.questions.all?(&:valid?)
      Test.transaction do
        @test.save!
        @test.questions.each(&:save!)
        @test.questions.update_all(deadline: @test.deadline)
      end
      if params[:publish].present?
        redirect_to @test, notice: "Тест опубликован."
      else
        redirect_to edit_test_path(@test), notice: "Тест обновлён."
      end
    else
      @questions = @test.questions.to_a
      flash.now[:alert] = @test.errors.full_messages.to_sentence.presence || "Не удалось сохранить. Повторите."
      render :edit, status: :unprocessable_entity
    end
  end

  # Drafts carry no attempts (answering needs publish), so dropping one is safe.
  # Published tests are never deleted here: attempts would go with them.
  def destroy
    @test = Test.find(params[:id])
    return head(:forbidden) unless @test.editable_by?(Current.user)
    return redirect_to tests_path, alert: "Опубликованный тест удалить нельзя." unless @test.draft?
    @test.destroy!
    redirect_to tests_path, notice: "Черновик удалён."
  end

  # All questions on one page, one submit for the whole test; scoreboard after deadline.
  # Drafts open only to the author.
  def show
    @test = Test.includes(:author, questions: :attempts).find(params[:id])
    if @test.draft? && !@test.editable_by?(Current.user)
      return redirect_to tests_path, alert: "Тест ещё не опубликован."
    end
    @questions = @test.questions.to_a
    return render_gate unless @test.unlocked?(Current.user, session)
    @my_attempts = Attempt.where(question: @questions, user: Current.user).index_by(&:question_id)
    @answered = @my_attempts.any?
    @scoreboard = build_scoreboard if @test.closed? && @test.published?
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
    return redirect_to @test, alert: "Тест ещё не опубликован." unless @test.published?
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

    # Whitelisted test form fields; published flips only through update.
    def test_params
      params.expect(test: [ :title, :body, :deadline, :password, :max_points ])
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
