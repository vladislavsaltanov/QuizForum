# Self-generation: asks the AI adapter for today's pack and feeds it through
# the same moderated intake as the webhook. Skips quietly when disabled,
# keyless, already created, or generation failed — the external cron over
# the webhook stays the fallback, never a duplicate.
class AiDailyGenerateJob < ApplicationJob
  queue_as :default

  # Builds today's pack; safe to run twice, the ingest keeps one copy.
  # force: true deletes the batch first and generates a fresh one right away.
  def perform(batch: AiQuestions.today.to_s, force: false)
    unless AiQuestions.generate_enabled?
      Rails.logger.info("[AI] generation skipped (disabled or no GEMINI_API_KEY).")
      return
    end
    batch = Date.iso8601(batch.to_s)
    if force
      deleted = Question.ai.where(ai_batch: batch).destroy_all.size
      Rails.logger.info("[AI] force: deleted #{deleted} questions for #{batch}.")
    elsif Question.ai.where(ai_batch: batch).exists?
      Rails.logger.info("[AI] pack for #{batch} already exists, skipping.")
      return
    end
    recent = Question.ai.order(deadline: :desc).limit(30).pluck(:title)
    Rails.logger.info("[AI] generating pack for #{batch}...")
    items = GeminiClient.new.generate_pack(recent_titles: recent)
    if items.nil?
      Rails.logger.error("[AI] generation failed, nothing ingested.")
      return
    end
    result = AiQuestionIngest.call(items:, batch:, source: "gemini")
    if result.errors.any?
      Rails.logger.error("[AI] ingest rejected pack: #{result.errors.join("; ")}")
    else
      Rails.logger.info("[AI] ingested #{result.questions.size} questions for #{batch}.")
    end
  rescue Date::Error
    nil
  end
end
