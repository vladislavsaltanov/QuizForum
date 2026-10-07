require "net/http"
require "json"
require "digest"

# Thin HTTP skin over coderunner /v1/run_check; thresholds live in server.py, not here.
# Transport failure returns nil: the job retries, the attempt stays pending.
class CodeRunnerClient
  Result = Data.define(:passed, :total, :deterministic, :needs_review, :reasons, :failed_sample)

  ENDPOINT = "/v1/run_check"
  OPEN_TIMEOUT = 2
  # 100 cases at ~2s each worst-case; the job is async, this only guards hangs.
  READ_TIMEOUT = 120

  # Main entry: diff-fuzz outcome for a reference/attempt pair, or nil when down.
  def run_check(reference:, attempt:, language:, reference_language:, seed:, cases: 100, read_timeout: READ_TIMEOUT)
    map(JSON.parse(post(reference:, attempt:, language:, reference_language:,
      seed:, cases:, read_timeout:)))
  rescue StandardError
    nil
  end

  # Coderunner URL, override with CODERUNNER_URL. Env only, never user input.
  def self.base_url
    ENV.fetch("CODERUNNER_URL", "http://localhost:8001")
  end

  private
    # Raw runner hash to Result; unknown shape means nil, never a guessed verdict.
    def map(payload)
      return nil unless payload.is_a?(Hash)
      return nil unless payload["passed"].is_a?(Integer) && payload["total"].is_a?(Integer)
      Result.new(payload["passed"], payload["total"], payload["deterministic"],
        payload["needs_review"], Array(payload["reasons"]), Array(payload["failed_sample"]))
    end

    # HTTP round-trip with one retry on timeouts; the queue does the rest.
    def post(reference:, attempt:, language:, reference_language:, seed:, cases:, read_timeout:)
      attempts = 0
      begin
        attempts += 1
        uri = URI("#{self.class.base_url}#{ENDPOINT}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = read_timeout
        req = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
        req.body = JSON.generate(key: idempotency_key(reference, attempt, seed),
          language:, reference_language:, reference:, attempt:, seed:, cases:)
        http.request(req).body
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED
        retry if attempts < 2
        raise
      end
    end

    # Stable key per reference/attempt/seed triple against double submits.
    def idempotency_key(reference, attempt, seed)
      "codecheck:#{Digest::SHA256.hexdigest("#{reference}\n#{attempt}\n#{seed}")[0, 16]}"
    end
end
