# AI question-of-the-day pack: env config and schedule math in one place.
module AiQuestions
  TAG = "ИИ"
  BOT_NAME = "Google Gemini"
  BOT_ROLE = "ИИ"
  BOT_EMAIL = "gemini@quizforum.local"
  PACK_SIZE = 9
  # Closed AI packs linger on the feed this long before the archive takes them
  # (humans get Question::ARCHIVE_GRACE).
  ARCHIVE_GRACE = 2.hours

  # Master kill switch; default on.
  def self.enabled?
    ENV.fetch("AI_QUESTIONS_ENABLED", "1") != "0"
  end

  # Zone the 17:00/15:00 cycle is counted in; default Moscow, configurable.
  def self.zone
    ENV.fetch("AI_TIME_ZONE", "Europe/Moscow")
  end

  # Days an archived AI pack survives before the retention job deletes it.
  def self.retention_days
    ENV.fetch("AI_RETENTION_DAYS", "3").to_i
  end

  # Outgoing self-generation runs only with a Gemini key on board.
  def self.generate_enabled?
    enabled? && ENV["GEMINI_API_KEY"].present?
  end

  # Webhook auth token; blank means the endpoint stays closed.
  def self.ingest_token
    ENV["AI_INGEST_TOKEN"].to_s
  end

  # Pack created 17:00 on +batch+, closes next day 15:00 zone time.
  def self.deadline_for(batch)
    Time.use_zone(zone) { Time.zone.local(batch.year, batch.month, batch.day, 15, 0) + 1.day }
  end

  # Today's pack date in the AI zone.
  def self.today
    Time.use_zone(zone) { Time.zone.today }
  end

  # The bot author AI packs are published under.
  def self.bot_user!
    User.find_or_create_by!(email: BOT_EMAIL) do |u|
      u.name = BOT_NAME
      u.display_role = BOT_ROLE
      u.password = SecureRandom.hex(32)
      u.email_confirmed_at = Time.current
    end
  end
end
