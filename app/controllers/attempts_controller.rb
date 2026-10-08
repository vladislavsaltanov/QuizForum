# One immutable attempt per user per question; choice grading happens in the model.
class AttemptsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: %i[create verdict],
             with: -> { redirect_back fallback_location: root_path, alert: "Попробуйте позже." }

  # Saves the current user's attempt. Rejects late posts; the model rejects duplicates.
  def create
    @question = Question.find(params[:question_id])
    return redirect_to @question, alert: "Дедлайн прошёл." if @question.closed?
    @attempt = @question.attempts.build(attempt_params.merge(user: Current.user))
    if @question.code? && !language_allowed?
      @attempt.errors.add(:language, :inclusion)
      return redirect_to @question, alert: @attempt.errors.full_messages.to_sentence
    end
    if @attempt.save
      if @question.code?
        AttemptCodeCheckJob.perform_later(@attempt.id)
        redirect_to @question, notice: "Ответ отправлен на проверку."
      elsif @question.choice?
        # Choice verdicts are already set; no job.
        redirect_to @question, notice: "Ответ отправлен на модерацию."
      else
        # Text answers go to the OpenJev jury.
        AttemptJuryJob.perform_later(@attempt.id)
        redirect_to @question, notice: "Ответ отправлен на модерацию."
      end
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
    Turbo::StreamsChannel.broadcast_refresh_to("leaderboard") if @attempt.revealed_correct?
    @attempt.broadcast_verdict_change if @attempt.question.closed?
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

    # Only runner-gradeable languages pass; empty allowlist means any of those.
    def language_allowed?
      lang = attempt_params[:language]
      return false unless CodeRunnerClient::SUPPORTED_LANGUAGES.include?(lang)
      allowed = Array(@question.code_languages)
      allowed.empty? || allowed.include?(lang)
    end
end
