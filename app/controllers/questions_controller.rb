# Public question pages with deadline-based visibility of answers and comments.
class QuestionsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: %i[create update],
             with: -> { redirect_back fallback_location: root_path, alert: "Попробуйте позже." }

  # Assembles one question page; what respondents see depends on the deadline.
  def show
    @question = Question.find(params[:id])
    # Privileged viewers (author, trustee, admin) see answers, reference, and comments.
    @is_author = @question.privileged?(Current.user)
    @tab = params[:tab] == "comments" ? "comments" : "answers"
    @my_attempt = @question.attempts.find_by(user: Current.user)
    @attempts = visible_attempts
    @respondent_names = respondent_names
    @comments = visible_comments
    @stats = @question.attempts.group(:verdict).count if @question.closed? || @is_author
  end

  # Blank form prefilled with a one-week deadline.
  def new
    @question = Question.new(deadline: 7.days.from_now.change(sec: 0))
  end

  # Publishes a question; trustee list syncs only when the form sent the field.
  def create
    @question = Current.user.authored_questions.build(question_params)
    @question.tags = params[:question][:tags_string].to_s.split(",").map(&:strip).reject(&:empty?)
    @question.options = parse_options if @question.choice?
    moderation_blocked? if @question.valid?
    if @question.errors.empty? && @question.save
      _, trustee_alert = @question.sync_trustees_by_emails(params[:question][:trustee_emails]) if params[:question].key?(:trustee_emails)
      redirect_to @question, notice: "Вопрос опубликован.", alert: trustee_alert
    else
      flash.now[:alert] = @question.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  # Edit form; the trustee block renders for author/admin only.
  def edit
    @question = Question.find(params[:id])
    head(:forbidden) unless privileged?(@question)
    @can_manage_trustees = @question.managed_by?(Current.user)
  end

  # Saves edits; only author/admin may change the trustee list.
  def update
    @question = Question.find(params[:id])
    return head(:forbidden) unless privileged?(@question)
    @question.assign_attributes(question_params)
    @question.tags = params[:question][:tags_string].to_s.split(",").map(&:strip).reject(&:empty?)
    @question.options = parse_options if @question.choice?
    moderation_blocked? if @question.valid?
    if @question.errors.empty? && @question.save
      if params[:question].key?(:trustee_emails) && @question.managed_by?(Current.user)
        _, trustee_alert = @question.sync_trustees_by_emails(params[:question][:trustee_emails])
      end
      redirect_to @question, notice: "Вопрос обновлён.", alert: trustee_alert
    else
      @can_manage_trustees = @question.managed_by?(Current.user)
      flash.now[:alert] = @question.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  # Deletes the question with its attempts and comments.
  def destroy
    @question = Question.find(params[:id])
    return head(:forbidden) unless privileged?(@question)
    @question.destroy!
    redirect_to root_path, notice: "Вопрос удалён."
  end

  private
    # Laya sync-gate on public text including reference and explanation.
    def moderation_blocked?
      moderation_text = [ @question.title, @question.body, @question.tags.join(" "),
                      @question.reference_answer, @question.explanation ].join("\n")
      verdict = ModerationClient.check(text: moderation_text)
      @question.errors.add(:base, "Отклонено проверкой: #{verdict.category}.") if verdict.verdict == :reject
      @question.errors.add(:base, "Проверка не удалась, попробуйте позже.") if verdict.verdict == :try_later
      verdict.verdict == :reject || verdict.verdict == :try_later
    end

    # Author-or-trustee-or-admin gate shared by the write actions.
    def privileged?(question)
      question.privileged?(Current.user)
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

    # Approved plus own comments pre-deadline; everything after reveal.
    def visible_comments
      scope = @question.comments.includes(:user).order(:created_at)
      return scope if @question.closed? || @is_author
      scope.where(status: "approved").or(scope.where(user: Current.user))
    end

    # Whitelisted question form fields.
    def question_params
      params.expect(question: [ :title, :body, :answer_type, :deadline, :reference_answer, :explanation ])
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
