require "net/http"
require "json"
require "digest"

# Sync Laya verdict before INSERT; any transport error fails closed.
class ModerationClient
  Result = Data.define(:verdict, :category)

  ENDPOINT = "/v1/judge"
  OPEN_TIMEOUT = 2
  READ_TIMEOUT = 10

  def self.check(text:, question: nil)
    new.check(text:, question:)
  end

  def self.base_url
    ENV.fetch("LAYA_SIDECAR_URL", "http://localhost:8000")
  end

  def check(text:, question: nil)
    map(JSON.parse(post(text:, question:)))
  rescue StandardError
    Result.new(:try_later, "недоступна")
  end

  private
    # Maps sidecar payload to pass/review/reject; public text only ever rejects.
    def map(payload)
      return Result.new(:reject, payload["category"] || "нарушение") if payload["verdict"] == "reject"
      return Result.new(:review, "на проверке") if payload["needs_review"]
      Result.new(:pass, "")
    end

    def post(text:, question:)
      uri = URI("#{self.class.base_url}#{ENDPOINT}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      req = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
      req.body = JSON.generate(key: idempotency_key(text), candidate: text,
                               question:, presets: %w[moderation_questions guard_questions])
      http.request(req).body
    end

    def idempotency_key(text)
      "comment:#{Digest::SHA256.hexdigest(text.to_s)[0, 16]}"
    end
end
