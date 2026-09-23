# Grades one text attempt via the OpenJev sidecar; fail-open by design.
class AttemptJuryJob < ApplicationJob
  queue_as :default

  # Transport-shaped failure; the attempt simply stays pending for the author.
  class GradeFailed < StandardError; end

  retry_on GradeFailed, wait: :polynomially_longer, attempts: 5

  MAX_BODY_CHARS = 8000

  # Writes the jury suggestion always, the verdict only when confident and still pending.
  def perform(attempt_id)
    attempt = Attempt.find(attempt_id)
    result = JuryClient.new.grade(reference: attempt.question.reference_answer,
      answer: attempt.body.to_s.truncate(MAX_BODY_CHARS))
    raise GradeFailed, "jury sidecar unavailable" if result.nil?
    attempt.update!(jury_label: result.label, jury_score: result.score,
      jury_needs_review: result.needs_review, jury_reasons: reasons_text(result))
    verdict = map_verdict(result)
    # Conditional write: a late job never overwrites the author's verdict.
    Attempt.where(id: attempt.id, verdict: "pending")
      .update_all(verdict:, updated_at: Time.current) if verdict
  end

  private
    # Confident jury outcomes map to verdicts; anything under review maps to nothing.
    def map_verdict(result)
      return "correct" if result.label == "positive" && !result.needs_review
      return "incorrect" if result.label == "false" && !result.needs_review
      nil
    end

    # Review reasons plus uncovered points, one per line for the author's block.
    def reasons_text(result)
      (result.reasons + result.missing_points.map { "Не покрыто: #{it}" }).join("\n").presence
    end
end
