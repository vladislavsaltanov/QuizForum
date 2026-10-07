# Forced AI pack regeneration: deletes the batch (default today) at once and
# requests a fresh one immediately, no waiting for the schedule.
# Usage: bin/rails ai:regenerate          # today's pack
#        bin/rails "ai:regenerate[2026-10-05]"
namespace :ai do
  desc "Delete the AI pack for DATE (default today) and generate a fresh one now"
  task :regenerate, [ :date ] => :environment do |_, args|
    # Rake logs to the log file only; mirror job logs to the console too.
    Rails.logger.broadcast_to(ActiveSupport::Logger.new($stdout))
    batch = args[:date].present? ? Date.iso8601(args[:date]) : AiQuestions.today
    deleted = Question.ai.where(ai_batch: batch).destroy_all.size
    puts "Deleted #{deleted} AI questions for #{batch}."
    AiDailyGenerateJob.perform_now(batch: batch.to_s, force: true)
    puts "Pack now holds #{Question.ai.where(ai_batch: batch).count} AI questions."
  rescue Date::Error
    abort "DATE must be YYYY-MM-DD, got #{args[:date].inspect}."
  end
end

namespace :ai do
  desc "Generate today's AI pack first, then wipe other open AI packs only on success (humans and revealed packs untouched)"
  task refresh: :environment do
    # Rake logs to the log file only; mirror job logs to the console too.
    Rails.logger.broadcast_to(ActiveSupport::Logger.new($stdout))
    batch = AiQuestions.today
    # Generate first without wiping: the job never deletes unless forced,
    # so a failed generation leaves every existing pack untouched.
    AiDailyGenerateJob.perform_now(batch: batch.to_s)
    fresh = Question.ai.where(ai_batch: batch)
    if fresh.count == AiQuestions::PACK_SIZE
      wiped = Question.ai.where("questions.deadline > ?", Time.current).where.not(ai_batch: batch).destroy_all.size
      puts "Deleted #{wiped} stale open AI questions."
    else
      puts "Generation failed or incomplete; old packs left untouched."
    end
    puts "Today's pack now holds #{fresh.count} AI questions."
  end
end
