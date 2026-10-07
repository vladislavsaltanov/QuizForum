require "test_helper"

class AttemptCodeCheckJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @question = users(:one).authored_questions.create!(title: "Сложите два числа",
      body: "Напишите solve(a, b).", answer_type: "code", deadline: 7.days.from_now,
      reference_answer: "def solve(a, b):\n  return a + b",
      code_languages: [ "python" ], reference_language: "python")
    @attempt = @question.attempts.create!(user: users(:two),
      body: "def solve(a, b):\n  return a + b", language: "python")
  end

  test "confident pass writes correct and code columns" do
    with_check(check_result(3, 3, false)) do
      AttemptCodeCheckJob.perform_now(@attempt.id)
    end

    @attempt.reload
    assert_equal "correct", @attempt.verdict
    assert_equal 3, @attempt.code_passed
    assert_equal 3, @attempt.code_total
    assert_not @attempt.code_needs_review
  end

  test "confident fail writes incorrect and code columns" do
    with_check(check_result(0, 3, false)) do
      AttemptCodeCheckJob.perform_now(@attempt.id)
    end

    @attempt.reload
    assert_equal "incorrect", @attempt.verdict
    assert_equal 0, @attempt.code_passed
    assert_equal 3, @attempt.code_total
  end

  test "middle score writes partial" do
    with_check(check_result(1, 3, false)) do
      AttemptCodeCheckJob.perform_now(@attempt.id)
    end

    @attempt.reload
    assert_equal "partial", @attempt.verdict
    assert_equal 1, @attempt.code_passed
  end

  test "review keeps pending but stores suggestion" do
    with_check(check_result(3, 3, true, reasons: [ "passed 2 of 3 cases" ])) do
      AttemptCodeCheckJob.perform_now(@attempt.id)
    end

    @attempt.reload
    assert_equal "pending", @attempt.verdict
    assert_equal 3, @attempt.code_passed
    assert @attempt.code_needs_review
    assert_includes @attempt.code_reasons, "passed 2 of 3 cases"
  end

  test "failing result under review keeps pending" do
    with_check(check_result(0, 3, true, reasons: [ "reference is nondeterministic" ])) do
      AttemptCodeCheckJob.perform_now(@attempt.id)
    end

    assert_equal "pending", @attempt.reload.verdict
  end

  test "runner down keeps pending with blank code columns and retries" do
    with_check(nil) do
      assert_enqueued_jobs 1, only: AttemptCodeCheckJob do
        AttemptCodeCheckJob.perform_now(@attempt.id)
      end
    end

    @attempt.reload
    assert_equal "pending", @attempt.verdict
    assert_nil @attempt.code_passed
  end

  test "author verdict survives late job" do
    @attempt.update!(verdict: "incorrect")
    with_check(check_result(3, 3, false)) do
      AttemptCodeCheckJob.perform_now(@attempt.id)
    end

    @attempt.reload
    assert_equal "incorrect", @attempt.verdict
    assert_equal 3, @attempt.code_passed
  end

  test "rejected injection never reaches the runner and stays pending" do
    CodeRunnerClient.define_singleton_method(:new) do |*|
      fake = Object.new
      fake.define_singleton_method(:run_check) { |*_, **_| flunk "rejected text reached the runner" }
      fake
    end
    with_screen(ModerationClient::Result.new(:reject, "prompt_injection")) do
      AttemptCodeCheckJob.perform_now(@attempt.id)
    end

    @attempt.reload
    assert_equal "pending", @attempt.verdict
    assert_nil @attempt.code_passed
  ensure
    CodeRunnerClient.define_singleton_method(:new, ORIGINAL_CHECK_NEW)
  end

  test "screen review forces needs_review on confident pass" do
    with_screen(ModerationClient::Result.new(:review, "на проверке")) do
      with_check(check_result(3, 3, false)) { AttemptCodeCheckJob.perform_now(@attempt.id) }
    end

    @attempt.reload
    assert_equal "pending", @attempt.verdict
    assert_equal 3, @attempt.code_passed
    assert @attempt.code_needs_review
  end

  test "screen try_later still grades normally" do
    with_screen(ModerationClient::Result.new(:try_later, "недоступна")) do
      with_check(check_result(3, 3, false)) { AttemptCodeCheckJob.perform_now(@attempt.id) }
    end

    assert_equal "correct", @attempt.reload.verdict
  end

  test "confident pass on revealed question broadcasts leaderboard refresh" do
    @question.update!(deadline: 1.day.ago)
    with_check(check_result(3, 3, false)) do
      assert_turbo_stream_broadcasts "leaderboard" do
        AttemptCodeCheckJob.perform_now(@attempt.id)
      end
    end

    assert_equal "correct", @attempt.reload.verdict
  end

  test "confident pass on open question broadcasts own chip only" do
    with_check(check_result(3, 3, false)) do
      assert_no_turbo_stream_broadcasts "leaderboard" do
        # One replace for the page chip, one for the checking-modal copy.
        assert_turbo_stream_broadcasts @question, count: 2 do
          AttemptCodeCheckJob.perform_now(@attempt.id)
        end
      end
    end
  end

  test "confident pass on revealed question streams verdict chips and stats" do
    @question.update!(deadline: 1.day.ago)
    with_check(check_result(3, 3, false)) do
      assert_turbo_stream_broadcasts @question, count: 5 do
        AttemptCodeCheckJob.perform_now(@attempt.id)
      end
    end
  end

  test "truncates long bodies exactly like the jury job" do
    # Reference allows 20000 chars, so overlong references reach both jobs;
    # bodies cap at 8000 and ride along at max length.
    long_body = "x" * 8000
    long_ref = "y" * 9000
    @question.update!(reference_answer: long_ref)
    @attempt.update!(body: long_body)
    sent_check = nil
    fake_check = Object.new
    fake_check.define_singleton_method(:run_check) do |**kw|
      sent_check = kw
      CodeRunnerClient::Result.new(2, 2, true, false, [], [])
    end
    CodeRunnerClient.define_singleton_method(:new) { |*_| fake_check }
    begin
      AttemptCodeCheckJob.perform_now(@attempt.id)
    ensure
      CodeRunnerClient.define_singleton_method(:new, ORIGINAL_CHECK_NEW)
    end

    text_question = questions(:open_text)
    text_question.update!(reference_answer: long_ref)
    text_attempt = text_question.attempts.create!(user: users(:two), body: long_body)
    sent_jury = nil
    fake_jury = Object.new
    fake_jury.define_singleton_method(:grade) do |**kw|
      sent_jury = kw
      JuryClient::Result.new("positive", 1.0, false, [], [])
    end
    JuryClient.define_singleton_method(:new) { |*_| fake_jury }
    begin
      AttemptJuryJob.perform_now(text_attempt.id)
    ensure
      JuryClient.define_singleton_method(:new, ORIGINAL_JURY_NEW)
    end

    assert_equal long_ref, sent_check[:reference]
    assert_equal sent_jury[:reference], sent_check[:reference]
    assert_equal long_body.truncate(8000), sent_check[:attempt]
    assert_equal sent_jury[:answer], sent_check[:attempt]
  end

  test "job after deadline still grades a timely attempt" do
    @question.update!(deadline: 1.day.ago)
    with_check(check_result(3, 3, false)) do
      AttemptCodeCheckJob.perform_now(@attempt.id)
    end

    @attempt.reload
    assert_equal "correct", @attempt.verdict
    assert @attempt.revealed_correct?
  end

  test "double submit keeps one row" do
    assert_no_difference("Attempt.count") do
      dup = @question.attempts.build(user: users(:two),
        body: "def solve(a, b):\n  return a - b", language: "python")
      assert_not dup.save
    end
  end

  private
    ORIGINAL_CHECK_NEW = CodeRunnerClient.method(:new)
    ORIGINAL_JURY_NEW = JuryClient.method(:new)
    ORIGINAL_CHECK = ModerationClient.method(:check)

    def check_result(passed, total, review, reasons: [])
      CodeRunnerClient::Result.new(passed, total, true, review, reasons, [])
    end

    def with_screen(result)
      ModerationClient.define_singleton_method(:check) { |*_, **_| result }
      yield
    ensure
      ModerationClient.define_singleton_method(:check, ORIGINAL_CHECK)
    end

    def with_check(result)
      fake = Object.new
      fake.define_singleton_method(:run_check) { |*_, **_| result }
      CodeRunnerClient.define_singleton_method(:new) { |*_| fake }
      yield
    ensure
      CodeRunnerClient.define_singleton_method(:new, ORIGINAL_CHECK_NEW)
    end
end
