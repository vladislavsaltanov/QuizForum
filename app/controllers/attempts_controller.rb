class AttemptsController < ApplicationController
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
    def attempt_params
      params.expect(attempt: [ :body, :language, { selected: [] } ])
    end
end
