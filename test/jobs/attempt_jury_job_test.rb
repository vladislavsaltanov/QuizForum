require "test_helper"

class AttemptJuryJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @attempt = Attempt.create!(question: questions(:open_text),
      user: users(:two), body: "Париж — столица Франции.")
  end

  test "confident positive writes correct and jury columns" do
    with_grade(jury_result("positive", 1.0, false)) do
      AttemptJuryJob.perform_now(@attempt.id)
    end

    @attempt.reload
    assert_equal "correct", @attempt.verdict
    assert_equal "positive", @attempt.jury_label
    assert_equal 1.0, @attempt.jury_score
    assert_not @attempt.jury_needs_review
  end

  test "confident false writes incorrect" do
    with_grade(jury_result("false", 0.0, false)) do
      AttemptJuryJob.perform_now(@attempt.id)
    end

    assert_equal "incorrect", @attempt.reload.verdict
  end

  test "review keeps pending but stores suggestion" do
    result = jury_result("partial", 0.5, true,
      reasons: [ "покрыта часть пунктов" ], missing: [ "Индекс занимает место" ])
    with_grade(result) { AttemptJuryJob.perform_now(@attempt.id) }

    @attempt.reload
    assert_equal "pending", @attempt.verdict
    assert_equal "partial", @attempt.jury_label
    assert @attempt.jury_needs_review
    assert_includes @attempt.jury_reasons, "покрыта часть пунктов"
    assert_includes @attempt.jury_reasons, "Индекс занимает место"
  end

  test "sidecar down keeps pending with blank jury and retries" do
    with_grade(nil) do
      assert_enqueued_jobs 1, only: AttemptJuryJob do
        AttemptJuryJob.perform_now(@attempt.id)
      end
    end

    @attempt.reload
    assert_equal "pending", @attempt.verdict
    assert_nil @attempt.jury_label
  end

  test "author verdict survives late job" do
    @attempt.update!(verdict: "incorrect")
    with_grade(jury_result("positive", 1.0, false)) do
      AttemptJuryJob.perform_now(@attempt.id)
    end

    @attempt.reload
    assert_equal "incorrect", @attempt.verdict
    assert_equal "positive", @attempt.jury_label
  end

  private
    ORIGINAL_NEW = JuryClient.method(:new)

    def jury_result(label, score, review, reasons: [], missing: [])
      JuryClient::Result.new(label, score, review, reasons, missing)
    end

    def with_grade(result)
      fake = Object.new
      fake.define_singleton_method(:grade) { |*_, **_| result }
      JuryClient.define_singleton_method(:new) { |*_| fake }
      yield
    ensure
      JuryClient.define_singleton_method(:new, ORIGINAL_NEW)
    end
end
