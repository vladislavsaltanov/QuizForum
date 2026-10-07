# Grades one code attempt via the coderunner diff-fuzz service; fail-open by design.
class AttemptCodeCheckJob < ApplicationJob
  queue_as :default

  # Transport-shaped failure; the attempt simply stays pending for the author.
  class CheckFailed < StandardError; end

  retry_on CheckFailed, wait: :polynomially_longer, attempts: 5

  # Same cap as the jury path so long bodies behave identically.
  MAX_BODY_CHARS = AttemptJuryJob::MAX_BODY_CHARS
  # Full grading budget (spec N=100); the question dry-run uses the smoke budget.
  FULL_CASES = 100
  SMOKE_CASES = 10

  # Writes the code columns always, the verdict only when decisive and still pending.
  def perform(attempt_id)
    attempt = Attempt.find(attempt_id)
    question = attempt.question
    # A rejected screen never blocks grading: sandboxed execution is safe and
    # the verdict is factual (repetitive code trips the spam preset). The flag
    # forces author review instead.
    screen = ModerationClient.check(text: attempt.body.to_s.truncate(MAX_BODY_CHARS),
      presets: %w[moderation_questions])
    forced_review = screen.verdict == :reject && code_review_worthy?(screen.category) ? "модерация: #{screen.category}" : nil
    attempt_lang = attempt.language.presence || question.reference_language.presence || "python"
    reference_lang = question.reference_language.presence || attempt_lang
    result = CodeRunnerClient.new.run_check(
      reference: question.reference_answer.to_s,
      attempt: attempt.body.to_s.truncate(MAX_BODY_CHARS),
      language: attempt_lang, reference_language: reference_lang,
      seed: question.id, cases: FULL_CASES)
    raise CheckFailed, "coderunner unavailable" if result.nil?
    needs_review = result.needs_review || screen.verdict == :review || forced_review
    reasons = (result.reasons + [ forced_review ].compact).join("\n").presence
    # update_columns: grading columns only, never revalidates the frozen body.
    attempt.update_columns(code_passed: result.passed, code_total: result.total,
      code_needs_review: needs_review, code_reasons: reasons,
      updated_at: Time.current)
    verdict = map_verdict(result, needs_review)
    return unless verdict
    # Conditional write: a late job never overwrites the author's verdict.
    updated = Attempt.where(id: attempt.id, verdict: "pending")
      .update_all(verdict:, updated_at: Time.current)
    return unless updated == 1
    reloaded = attempt.reload
    Turbo::StreamsChannel.broadcast_refresh_to("leaderboard") if reloaded.revealed_correct?
    reloaded.broadcast_verdict_change if reloaded.question.closed?
  end

  private
    # Screens meaningless for executed code (repetitive programs trip them);
    # toxicity, threats, slurs and secrets still force author review.
    def code_review_worthy?(category)
      ![ "спам", "внедрение инструкций", "попытка обхода", "оффтопик" ].include?(category.to_s)
    end

    # Decisive runner outcomes map to verdicts; anything under review maps to nothing.
    def map_verdict(result, needs_review)
      return if needs_review
      return "correct" if result.total.to_i > 0 && result.passed == result.total
      return "incorrect" if result.passed == 0
      "partial"
    end
end
