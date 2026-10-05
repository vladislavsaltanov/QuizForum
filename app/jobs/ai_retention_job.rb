# Garbage collection for AI packs: archived packs older than AI_RETENTION_DAYS
# are hard-deleted with their attempts and comments so the archive never rots.
class AiRetentionJob < ApplicationJob
  queue_as :default

  # Destroys AI packs archived longer than the retention window; returns the count.
  def perform
    return 0 unless AiQuestions.enabled?
    Question.ai.where("questions.deadline < ?", AiQuestions.retention_days.days.ago).destroy_all.size
  end
end
