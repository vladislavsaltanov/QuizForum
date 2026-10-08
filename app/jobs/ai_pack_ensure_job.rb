# Hourly backfill for AI packs: generates the newest batch whose window is
# still open when no pack exists. Expired dates stay missing by design —
# a pack born past its deadline would close instantly.
class AiPackEnsureJob < ApplicationJob
  queue_as :default

  def perform
    [ AiQuestions.today, AiQuestions.today - 1 ].each do |batch|
      next if AiQuestions.deadline_for(batch) <= Time.current
      next if Question.ai.where(ai_batch: batch).exists?
      AiDailyGenerateJob.perform_now(batch: batch.to_s)
      return
    end
  end
end
