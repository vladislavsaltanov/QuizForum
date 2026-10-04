require "net/http"
require "json"
require "digest"

# Sync Laya verdict before INSERT; any transport error fails closed.
class ModerationClient
  Result = Data.define(:verdict, :category)

  CATEGORY_NAMES = {
    "toxic" => "токсичность", "harassment" => "травля", "threat" => "угрозы",
    "spam" => "спам", "jailbreak" => "попытка обхода",
    "prompt_injection" => "внедрение инструкций", "sensitive_data" => "личные данные",
    "severity" => "вредный контент", "harm_severity" => "вредный контент", "topic" => "оффтопик",
    "мат" => "мат"
  }.freeze

  ENDPOINT = "/v1/judge"
  OPEN_TIMEOUT = 2
  READ_TIMEOUT = 10

  # Main entry: verdict for a text, fail-closed. Attempts pass the full
  # guard set (prompt-injection screening); author text stays on the
  # limited set that never false-rejects well-formed questions.
  def self.check(text:, question: nil, presets: %w[moderation_questions])
    return Result.new(:pass, "") if bypass?
    new.check(text:, question:, presets:)
  end

  # Dev escape hatch without a sidecar; never bypasses in production.
  def self.bypass?
    !Rails.env.production? && ENV["MODERATION_OFF"] == "1"
  end

  # Sidecar URL, override with LAYA_SIDECAR_URL.
  def self.base_url
    ENV.fetch("LAYA_SIDECAR_URL", "http://localhost:8000")
  end

  # Posts the payload; any transport error fails closed.
  def check(text:, question: nil, presets: %w[moderation_questions])
    map(JSON.parse(post(text:, question:, presets:)))
  rescue StandardError
    Result.new(:try_later, "недоступна")
  end

  private
    # Maps sidecar payload to pass/review/reject; public text only ever rejects.
    def map(payload)
      return Result.new(:try_later, "недоступна") unless payload.is_a?(Hash)
      return Result.new(:reject, human_category(payload["category"])) if payload["verdict"] == "reject"
      return Result.new(:review, "на проверке") if payload["needs_review"]
      Result.new(:pass, "")
    end

    # Single HTTP round-trip with timeouts.
    def post(text:, question:, presets:)
      uri = URI("#{self.class.base_url}#{ENDPOINT}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      req = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
      req.body = JSON.generate(key: idempotency_key(text), candidate: text,
                               question:, presets:)
      http.request(req).body
    end

    # Preset name to Russian label; unknown means violation.
    def human_category(raw)
      CATEGORY_NAMES.fetch(raw.to_s, "нарушение")
    end

    # Stable key per text against double submits.
    def idempotency_key(text)
      "mod:#{Digest::SHA256.hexdigest(text.to_s)[0, 16]}"
    end
end
