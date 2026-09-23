require "net/http"
require "json"
require "digest"

# Thin HTTP skin over sidecar /v1/grade; thresholds live in grade.py, not here.
# Transport failure returns nil: the job retries, the attempt stays pending.
class JuryClient
  Result = Data.define(:label, :score, :needs_review, :reasons, :missing_points)

  LABELS = %w[positive partial false].freeze

  ENDPOINT = "/v1/grade"
  OPEN_TIMEOUT = 2
  # CPU inference runs tens of seconds; the job is async, this only guards hangs.
  READ_TIMEOUT = 180

  # Main entry: grade_v2 outcome for a reference/answer pair, or nil when down.
  def grade(reference:, answer:, points_text: "")
    map(JSON.parse(post(reference:, answer:, points_text:)))
  rescue StandardError
    nil
  end

  # Sidecar URL, override with JURY_SIDECAR_URL. Env only, never user input.
  def self.base_url
    ENV.fetch("JURY_SIDECAR_URL", "http://localhost:8000")
  end

  private
    # Raw sidecar hash to Result; unknown shape means nil, never a guessed verdict.
    def map(payload)
      return nil unless payload.is_a?(Hash)
      return nil unless LABELS.include?(payload["label"])
      Result.new(payload["label"], payload["score"], payload["needs_review"],
        Array(payload["review_reasons"]), Array(payload["missing_points"]))
    end

    # HTTP round-trip with one retry on timeouts; the queue does the rest.
    def post(reference:, answer:, points_text:)
      attempts = 0
      begin
        attempts += 1
        uri = URI("#{self.class.base_url}#{ENDPOINT}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        req = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
        req.body = JSON.generate(key: idempotency_key(reference, answer),
          reference:, answer:, points_text:)
        http.request(req).body
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED
        retry if attempts < 2
        raise
      end
    end

    # Stable key per reference/answer pair against double submits.
    def idempotency_key(reference, answer)
      "jury:#{Digest::SHA256.hexdigest("#{reference}\n#{answer}")[0, 16]}"
    end
end
