# Safety net behind the 17:00 pack hour: every 10 minutes checks today's pack
# and generates it when missing. Overlaps collapse on the generation lock
# inside AiDailyGenerateJob — a running generation means skip, never a double.
class AiPackWatchdogJob < ApplicationJob
  queue_as :default

  def perform
    batch = AiQuestions.today
    return unless AiQuestions.generate_enabled?
    return if Time.current < AiQuestions.pack_due_at(batch)
    return if Question.ai.where(ai_batch: batch).exists?
    AiDailyGenerateJob.perform_now(batch: batch.to_s)
  end
end
