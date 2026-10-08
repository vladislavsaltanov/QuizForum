# Re-enqueues code checks orphaned by exhausted retries; fail-open by design.
# Picks attempts the checker never wrote to (code_total nil), old enough that
# no live job can still own them. Checked-but-pending (needs_review) is the
# author's queue, never re-driven here.
class AttemptRecheckJob < ApplicationJob
  queue_as :default

  # Younger rows may still have a queued or retrying check; leave them alone.
  STALE_AFTER = 15.minutes
  # Cap per sweep against deadline stampedes.
  BATCH_LIMIT = 50

  def perform
    Attempt.joins(:question)
      .where(verdict: "pending", code_total: nil, questions: { answer_type: "code" })
      .where("attempts.updated_at < ?", STALE_AFTER.ago)
      .limit(BATCH_LIMIT)
      .each { |attempt| AttemptCodeCheckJob.perform_later(attempt.id) }
  end
end
