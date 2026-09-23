require "test_helper"

class ModerationClientTest < ActiveSupport::TestCase
  test "reject payload maps verdict and category" do
    result = check_with('{"verdict":"reject","category":"оскорбление"}')

    assert_equal :reject, result.verdict
    assert_equal "оскорбление", result.category
  end

  test "needs_review payload maps to review" do
    result = check_with('{"verdict":"pass","needs_review":true}')

    assert_equal :review, result.verdict
  end

  test "clean payload maps to pass" do
    result = check_with('{"verdict":"pass","needs_review":false}')

    assert_equal :pass, result.verdict
  end

  test "connection error fails closed to try_later" do
    client = ModerationClient.new
    client.define_singleton_method(:post) { |*_, **_| raise Errno::ECONNREFUSED }

    assert_equal :try_later, client.check(text: "привет").verdict
  end

  test "garbage response fails closed to try_later" do
    result = check_with("not json")

    assert_equal :try_later, result.verdict
  end

  test "same text yields same idempotency key" do
    assert_equal capture_key("привет"), capture_key("привет")
    assert_not_equal capture_key("привет"), capture_key("другой")
  end

  test "bypass flag skips network outside production" do
    unstub_moderation
    old = ENV.delete("MODERATION_OFF")
    assert_equal :try_later, ModerationClient.check(text: "x").verdict
    ENV["MODERATION_OFF"] = "1"
    assert_equal :pass, ModerationClient.check(text: "x").verdict
  ensure
    old.nil? ? ENV.delete("MODERATION_OFF") : ENV["MODERATION_OFF"] = old
  end

  private
    def check_with(body)
      client = ModerationClient.new
      client.define_singleton_method(:post) { |*_, **_| body }
      client.check(text: "привет")
    end

    def capture_key(text)
      captured = nil
      fake = Object.new
      fake.define_singleton_method(:open_timeout=) { |*| }
      fake.define_singleton_method(:read_timeout=) { |*| }
      fake.define_singleton_method(:request) do |req|
        captured = JSON.parse(req.body)["key"]
        Net::HTTPOK.new("1.1", 200, "OK").tap do |res|
          res.instance_variable_set(:@body, '{"verdict":"pass"}')
          res.instance_variable_set(:@read, true)
        end
      end
      Net::HTTP.define_singleton_method(:new) { |*_| fake }
      ModerationClient.new.check(text: text)
      captured
    ensure
      Net::HTTP.singleton_class.remove_method(:new)
    end
end
