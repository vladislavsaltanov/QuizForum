# One immutable attempt per user per question; choice grading happens in the model.
class AttemptsController < ApplicationController
  # Records the current user's attempt; model validations reject doubles and late posts.
  def create
    @question = Question.find(params[:question_id])
    @attempt = @question.attempts.build(attempt_params.merge(user: Current.user))
    if @attempt.save
      redirect_to @question, notice: "Ответ отправлен на модерацию."
    else
      redirect_to @question, alert: @attempt.errors.full_messages.to_sentence
    end
  end

  private
    # Whitelisted attempt form fields.
    def attempt_params
      params.expect(attempt: [ :body, :language, { selected: [] } ])
    end
end
