require "test_helper"

class JuryClientTest < ActiveSupport::TestCase
  test "positive payload maps label score and no review" do
    result = check_with(grade_json(label: "positive", score: 1.0, needs_review: false))

    assert_equal "positive", result.label
    assert_equal 1.0, result.score
    assert_not result.needs_review
  end

  test "review payload keeps reasons and missing points" do
    result = check_with(grade_json(label: "partial", score: 0.5, needs_review: true,
      reasons: [ "покрыта часть пунктов" ], missing: [ "Индекс занимает место" ]))

    assert_equal "partial", result.label
    assert result.needs_review
    assert_equal [ "покрыта часть пунктов" ], result.reasons
    assert_equal [ "Индекс занимает место" ], result.missing_points
  end

  test "unknown label returns nil" do
    assert_nil check_with(grade_json(label: "maybe", score: 0.5, needs_review: true))
  end

  test "garbage response returns nil" do
    assert_nil check_with("not json")
  end

  test "connection error returns nil" do
    client = JuryClient.new
    client.define_singleton_method(:post) { |*_, **_| raise Errno::ECONNREFUSED }

    assert_nil client.grade(reference: "эталон", answer: "ответ")
  end

  test "same body yields same idempotency key" do
    assert_equal capture_key("ответ"), capture_key("ответ")
    assert_not_equal capture_key("ответ"), capture_key("другой")
  end

  private
    def grade_json(label:, score:, needs_review:, reasons: [], missing: [])
      JSON.generate(label:, score:, needs_review:, review_reasons: reasons,
        points_source: "single", coverage_score: nil, points: [], missing_points: missing,
        legacy: {}, notes: [])
    end

    def check_with(body)
      client = JuryClient.new
      client.define_singleton_method(:post) { |*_, **_| body }
      client.grade(reference: "эталон", answer: "ответ")
    end

    def capture_key(answer)
      captured = nil
      fake = Object.new
      fake.define_singleton_method(:open_timeout=) { |*| }
      fake.define_singleton_method(:read_timeout=) { |*| }
      fake.define_singleton_method(:request) do |req|
        captured = JSON.parse(req.body)["key"]
        Net::HTTPOK.new("1.1", 200, "OK").tap do |res|
          res.instance_variable_set(:@body, grade_json(label: "positive", score: 1.0, needs_review: false))
          res.instance_variable_set(:@read, true)
        end
      end
      Net::HTTP.define_singleton_method(:new) { |*_| fake }
      JuryClient.new.grade(reference: "эталон", answer:)
      captured
    ensure
      Net::HTTP.singleton_class.remove_method(:new)
    end
end
