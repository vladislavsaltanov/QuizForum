# Public question pages with deadline-based visibility of answers and comments.
class QuestionsController < ApplicationController
  COMMENT_BATCH = 10
  # Dry-run smoke budget for code questions (spec section 3); full grading uses 120s.
  CODE_DRY_RUN_TIMEOUT = 10

  rate_limit to: 10, within: 3.minutes, only: %i[create update],
             with: -> { redirect_back fallback_location: root_path, alert: "Попробуйте позже." }

  # Assembles one question page; what respondents see depends on the deadline.
  def show
    @question = Question.find(params[:id])
    # Privileged viewers (author, trustee, admin) see answers, reference, and comments.
    @is_author = @question.privileged?(Current.user)
    @can_edit = @question.editable_by?(Current.user)
    @tab = params[:tab] == "comments" ? "comments" : "answers"
    @my_attempt = @question.attempts.find_by(user: Current.user)
    @attempts = visible_attempts
    @respondent_names = respondent_names
    @comments = visible_comments
    @comments_total = Comment.visible_for(@question, Current.user).count
    @has_older = @comments_total > @comments.size
    @stats = @question.attempts.group(:verdict).count if @question.closed? || @is_author
  end

  # Blank form prefilled with a one-week deadline.
  def new
    @question = Question.new(deadline: 7.days.from_now.change(sec: 0))
  end

  # Publishes a question; trustee list syncs only when the form sent the field.
  def create
    @question = Current.user.authored_questions.build(question_params)
    @question.tags = parse_tags
    @question.options = parse_options if @question.choice?
    moderation_blocked? if @question.valid?
    code_dry_run_blocked? if @question.errors.empty?
    saved, @trustee_alert = @question.errors.empty? ? save_with_trustees : [ false, nil ]
    if saved
      redirect_to @question, notice: "Вопрос опубликован.", alert: @trustee_alert
    else
      flash.now[:alert] = @question.errors.full_messages.to_sentence.presence || "Не удалось сохранить. Повторите."
      render :new, status: :unprocessable_entity
    end
  end

  # Edit form; the trustee block renders for author/admin only.
  def edit
    @question = Question.find(params[:id])
    head(:forbidden) unless editable?(@question)
    @can_manage_trustees = @question.managed_by?(Current.user)
  end

  # Saves edits; only author/admin may change the trustee list.
  def update
    @question = Question.find(params[:id])
    return head(:forbidden) unless editable?(@question)
    @question.assign_attributes(question_params)
    @question.tags = parse_tags
    @question.options = parse_options if @question.choice?
    moderation_blocked? if @question.valid?
    code_dry_run_blocked? if @question.errors.empty?
    saved, @trustee_alert = @question.errors.empty? ? save_with_trustees : [ false, nil ]
    if saved
      redirect_to @question, notice: "Вопрос обновлён.", alert: @trustee_alert
    else
      @can_manage_trustees = @question.managed_by?(Current.user)
      flash.now[:alert] = @question.errors.full_messages.to_sentence.presence || "Не удалось сохранить. Повторите."
      render :edit, status: :unprocessable_entity
    end
  end

  # Deletes the question with its attempts and comments.
  def destroy
    @question = Question.find(params[:id])
    return head(:forbidden) unless editable?(@question)
    @question.destroy!
    redirect_to root_path, notice: "Вопрос удалён."
  end

  private
    # Question row and trustee grants commit as one unit: a sync that blows up must
    # not leave a published question that nobody observes. requires_new keeps that
    # unit atomic even when the caller already sits inside another transaction.
    # Returns [saved, alert].
    def save_with_trustees
      Question.transaction(requires_new: true) do
        if @question.save
          [ true, trustee_sync_alert ]
        else
          [ false, nil ]
        end
      end
    rescue ActiveRecord::RecordNotUnique
      # Two saves raced on the unique grant index; the savepoint undid the question too.
      flash[:modal] = [ "Параллельное сохранение: список наблюдателей не применён. Повторите правку." ]
      [ false, nil ]
    end

    # nil when the form left the trustee field alone or the actor may not manage it.
    # Per-address reasons go to the modal, the one-line summary stays in the toast.
    def trustee_sync_alert
      return unless params[:question].key?(:trustee_emails)
      return unless @question.managed_by?(Current.user)
      _, alert, problems = @question.sync_trustees_by_emails(params[:question][:trustee_emails])
      flash[:modal] = problems if problems.any?
      alert
    end

    # Laya sync-gate on public text including reference and explanation.
    # Blob shape shared with AiQuestionIngest so both doors keep the same bar.
    def moderation_blocked?
      moderation_text = AiQuestionIngest.moderation_text(
        title: @question.title, body: @question.body, tags: @question.tags,
        reference_answer: @question.reference_answer, explanation: @question.explanation,
        example_input: @question.example_input, example_output: @question.example_output,
        options: @question.options)
      verdict = ModerationClient.check(text: moderation_text)
      @question.errors.add(:base, "Отклонено проверкой: #{verdict.category}.") if verdict.verdict == :reject
      @question.errors.add(:base, "Проверка не удалась, попробуйте позже.") if verdict.verdict == :try_later
      verdict.verdict == :reject || verdict.verdict == :try_later
    end

    # Smoke run of the reference against itself (~10 cases, 10s budget).
    # A hanging/crashing reference blocks the form; a down runner fails open.
    def code_dry_run_blocked?
      return false unless @question.code?
      lang = @question.reference_language.presence || Array(@question.code_languages).first || "python"
      code = @question.reference_answer.to_s
      result = CodeRunnerClient.new.run_check(reference: code, attempt: code,
        language: lang, reference_language: lang, seed: @question.id || 0,
        cases: AttemptCodeCheckJob::SMOKE_CASES, read_timeout: CODE_DRY_RUN_TIMEOUT)
      return false if result.nil?
      return false if !result.needs_review && result.total.to_i > 0 && result.passed == result.total
      @question.errors.add(:reference_answer,
        "не проходит пробный прогон (#{result.reasons.join('; ')}).")
      true
    end

    # Author-or-admin gate for the write actions; trustees stay read-only.
    def editable?(question)
      question.editable_by?(Current.user)
    end

    # Strangers see only their own attempts before the deadline; full list after reveal.
    def visible_attempts
      scope = @question.attempts.includes(:user).order(:created_at)
      return scope if @question.closed? || @is_author
      scope.where(user: Current.user)
    end

    # Names of other respondents shown pre-deadline in place of answer texts.
    def respondent_names
      return [] if @question.closed? || @is_author
      @question.attempts.joins(:user).where.not(user: Current.user).distinct.pluck("users.name")
    end

    # Newest batch, flipped for the chat; older ones arrive on scroll up.
    def visible_comments
      Comment.visible_for(@question, Current.user).includes(:user).order(id: :desc).limit(COMMENT_BATCH).reverse
    end

    # Whitelisted question form fields.
    def question_params
      params.expect(question: [ :title, :body, :answer_type, :deadline, :reference_answer,
        :explanation, :reference_language, :example_input, :example_output, { code_languages: [] } ])
    end

    # Difficulty arrives from its own select; typed difficulty words merge into it.
    def parse_tags
      tags = params[:question][:tags_string].to_s.split(",").map(&:strip).reject(&:empty?)
      tags -= Question::DIFFICULTIES
      difficulty = params[:question][:difficulty].to_s.strip
      tags << difficulty if Question::DIFFICULTIES.include?(difficulty)
      tags
    end

    # Zips parallel text/correct form arrays into option hashes, skipping blank rows.
    def parse_options
      texts = Array(params[:question][:options_text])
      correct = Array(params[:question][:options_correct]).reject { it.to_s.strip.empty? }.map(&:to_i)
      texts.each_with_index.filter_map do |text, i|
        text = text.to_s.strip
        next if text.empty?
        { "text" => text, "correct" => correct.include?(i) }
      end
    end
end
