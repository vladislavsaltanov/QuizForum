class QuestionsController < ApplicationController
  def show
    @question = Question.find(params[:id])
    @is_author = @question.author == Current.user
    @tab = params[:tab] == "comments" ? "comments" : "answers"
    @my_attempt = @question.attempts.find_by(user: Current.user)
    @attempts = visible_attempts
    @respondent_names = respondent_names
    @comments = visible_comments
    @stats = @question.attempts.group(:verdict).count if @question.closed? || @is_author
  end

  private
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
end
