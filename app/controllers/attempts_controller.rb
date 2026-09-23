# One immutable attempt per user per question; choice grading happens in the model.
class AttemptsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: %i[create verdict],
             with: -> { redirect_back fallback_location: root_path, alert: "Попробуйте позже." }

  # Records the current user's attempt; model validations reject doubles and late posts.
  def create
    @question = Question.find(params[:question_id])
    @attempt = @question.attempts.build(attempt_params.merge(user: Current.user))
    if @attempt.save
      # Text answers go to the OpenJev jury; choice verdicts are already set.
      AttemptJuryJob.perform_later(@attempt.id) unless @question.choice?
      redirect_to @question, notice: "Ответ отправлен на модерацию."
    else
      redirect_to @question, alert: @attempt.errors.full_messages.to_sentence
    end
  end

  # Sets the verdict by hand; author, trustee, or admin only, any value any time.
  def verdict
    @attempt = attempt_in_scope
    return head(:forbidden) unless @attempt.question.privileged?(Current.user)
    verdict = params.expect(attempt: [ :verdict ])[:verdict]
    return head(:bad_request) unless Attempt::MANUAL_VERDICTS.include?(verdict)
    @attempt.update!(verdict:)
    redirect_to @attempt.question, notice: "Оценка обновлена."
  end

  private
    # Attempt scoped to the question from the URL; tampered ids raise 404.
    def attempt_in_scope
      Question.find(params[:question_id]).attempts.find(params[:id])
    end

    # Whitelisted attempt form fields.
    def attempt_params
      params.expect(attempt: [ :body, :language, { selected: [] } ])
    end
end
