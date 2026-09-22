class QuestionsController < ApplicationController
  def show
    @question = Question.find(params[:id])
    # ponytail: admin sees everything author sees (answers, reference, comments)
    @is_author = @question.privileged?(Current.user)
    @tab = params[:tab] == "comments" ? "comments" : "answers"
    @my_attempt = @question.attempts.find_by(user: Current.user)
    @attempts = visible_attempts
    @respondent_names = respondent_names
    @comments = visible_comments
    @stats = @question.attempts.group(:verdict).count if @question.closed? || @is_author
  end

  def new
    @question = Question.new(deadline: 7.days.from_now.change(sec: 0))
  end

  def create
    @question = Current.user.authored_questions.build(question_params)
    @question.tags = params[:question][:tags_string].to_s.split(",").map(&:strip).reject(&:empty?)
    @question.options = parse_options if @question.choice?
    if @question.save
      redirect_to @question, notice: "Вопрос опубликован."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @question = Question.find(params[:id])
    head(:forbidden) unless privileged?(@question)
  end

  def update
    @question = Question.find(params[:id])
    return head(:forbidden) unless privileged?(@question)
    @question.assign_attributes(question_params)
    @question.tags = params[:question][:tags_string].to_s.split(",").map(&:strip).reject(&:empty?)
    @question.options = parse_options if @question.choice?
    if @question.save
      redirect_to @question, notice: "Вопрос обновлён."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @question = Question.find(params[:id])
    return head(:forbidden) unless privileged?(@question)
    @question.destroy!
    redirect_to root_path, notice: "Вопрос удалён."
  end

  private
    # ponytail: single gate for author-or-admin; views reuse @is_author, no extra branches
    def privileged?(question)
      question.privileged?(Current.user)
    end

    # Before deadline: identities only (author sees all). After: everything public.
    def visible_attempts
      scope = @question.attempts.includes(:user).order(:created_at)
      return scope if @question.closed? || @is_author
      scope.where(user: Current.user)
    end

    def respondent_names
      return [] if @question.closed? || @is_author
      @question.attempts.joins(:user).where.not(user: Current.user).distinct.pluck("users.name")
    end

    def visible_comments
      scope = @question.comments.includes(:user).order(:created_at)
      return scope if @question.closed? || @is_author
      scope.where(status: "approved").or(scope.where(user: Current.user))
    end

    def question_params
      params.expect(question: [ :title, :body, :answer_type, :deadline, :reference_answer, :explanation ])
    end

    # ponytail: blank rows dropped, correct flags bound by row index
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
