require "test_helper"

class CodeRunnerClientTest < ActiveSupport::TestCase
  test "pass payload maps counts and no review" do
    result = check_with(run_json(passed: 3, total: 3, needs_review: false))

    assert_equal 3, result.passed
    assert_equal 3, result.total
    assert_not result.needs_review
  end

  test "review payload keeps reasons and failed sample" do
    result = check_with(run_json(passed: 2, total: 3, needs_review: true,
      reasons: [ "case 3 differs" ], failed_sample: [ { "input" => "x" } ]))

    assert_equal 2, result.passed
    assert result.needs_review
    assert_equal [ "case 3 differs" ], result.reasons
    assert_equal [ { "input" => "x" } ], result.failed_sample
  end

  test "non-hash payload returns nil" do
    assert_nil check_with('"just a string"')
  end

  test "missing counts returns nil" do
    assert_nil check_with(JSON.generate(deterministic: true))
  end

  test "garbage response returns nil" do
    assert_nil check_with("not json")
  end

  test "connection error returns nil" do
    client = CodeRunnerClient.new
    client.define_singleton_method(:post) { |*_, **_| raise Errno::ECONNREFUSED }

    assert_nil client.run_check(reference: "ref", attempt: "att",
      language: "python", reference_language: "python", seed: 1)
  end

  test "same triple yields same idempotency key" do
    assert_equal capture_key("att"), capture_key("att")
    assert_not_equal capture_key("att"), capture_key("other")
  end

  test "base_url honours env override" do
    old = ENV["CODERUNNER_URL"]
    ENV["CODERUNNER_URL"] = "http://runner:9000"
    assert_equal "http://runner:9000", CodeRunnerClient.base_url
  ensure
    old.nil? ? ENV.delete("CODERUNNER_URL") : ENV["CODERUNNER_URL"] = old
  end

  test "forwards every supported language in the request body" do
    CodeRunnerClient::SUPPORTED_LANGUAGES.each do |lang|
      captured = nil
      fake = Object.new
      fake.define_singleton_method(:open_timeout=) { |*| }
      fake.define_singleton_method(:read_timeout=) { |*| }
      fake.define_singleton_method(:request) do |req|
        captured = JSON.parse(req.body)["language"]
        Net::HTTPOK.new("1.1", 200, "OK").tap do |res|
          res.instance_variable_set(:@body, run_json(passed: 1, total: 1, needs_review: false))
          res.instance_variable_set(:@read, true)
        end
      end
      Net::HTTP.define_singleton_method(:new) { |*_| fake }
      begin
        CodeRunnerClient.new.run_check(reference: "ref", attempt: "att",
          language: lang, reference_language: lang, seed: 1)
      ensure
        Net::HTTP.singleton_class.remove_method(:new) rescue nil
      end

      assert_equal lang, captured
    end
  end

  test "timeout retries once then succeeds" do
    calls = 0
    fake = Object.new
    fake.define_singleton_method(:open_timeout=) { |*| }
    fake.define_singleton_method(:read_timeout=) { |*| }
    fake.define_singleton_method(:request) do |_req|
      calls += 1
      raise Net::ReadTimeout if calls == 1
      Net::HTTPOK.new("1.1", 200, "OK").tap do |res|
        res.instance_variable_set(:@body, JSON.generate(passed: 3, total: 3,
          deterministic: true, needs_review: false, reasons: [], failed_sample: []))
        res.instance_variable_set(:@read, true)
      end
    end

    Net::HTTP.define_singleton_method(:new) { |*_| fake }
    result = CodeRunnerClient.new.run_check(reference: "ref", attempt: "att",
      language: "python", reference_language: "python", seed: 1)

    assert_equal 3, result.passed
    assert_equal 2, calls
  ensure
    Net::HTTP.singleton_class.remove_method(:new) rescue nil
  end

  private
    def run_json(passed:, total:, needs_review:, reasons: [], failed_sample: [])
      JSON.generate(passed:, total:, deterministic: true, needs_review:,
        reasons:, failed_sample:)
    end

    def check_with(body)
      client = CodeRunnerClient.new
      client.define_singleton_method(:post) { |*_, **_| body }
      client.run_check(reference: "ref", attempt: "att",
        language: "python", reference_language: "python", seed: 1)
    end

    def capture_key(attempt)
      captured = nil
      fake = Object.new
      fake.define_singleton_method(:open_timeout=) { |*| }
      fake.define_singleton_method(:read_timeout=) { |*| }
      fake.define_singleton_method(:request) do |req|
        captured = JSON.parse(req.body)["key"]
        Net::HTTPOK.new("1.1", 200, "OK").tap do |res|
          res.instance_variable_set(:@body, run_json(passed: 3, total: 3, needs_review: false))
          res.instance_variable_set(:@read, true)
        end
      end
      Net::HTTP.define_singleton_method(:new) { |*_| fake }
      CodeRunnerClient.new.run_check(reference: "ref", attempt:,
        language: "python", reference_language: "python", seed: 1)
      captured
    ensure
      Net::HTTP.singleton_class.remove_method(:new)


    end
end
