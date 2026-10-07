require "test_helper"

class AttemptRecheckJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @question = questions(:open_code)
    @user = users(:one)
  end

  test "re-enqueues stale unchecked code attempts" do
    attempt = Attempt.create!(question: @question, user: @user,
      body: "def solve(x):\n  return x", language: "python")
    attempt.update_columns(updated_at: 1.hour.ago)

    assert_enqueued_with(job: AttemptCodeCheckJob, args: [ attempt.id ]) do
      AttemptRecheckJob.perform_now
    end
  end

  test "ignores fresh unchecked attempts" do
    Attempt.create!(question: @question, user: @user,
      body: "def solve(x):\n  return x", language: "python")

    assert_no_enqueued_jobs(only: AttemptCodeCheckJob) do
      AttemptRecheckJob.perform_now
    end
  end

  test "ignores non-code attempts" do
    attempt = Attempt.create!(question: questions(:open_text), user: @user, body: "текст")
    attempt.update_columns(updated_at: 1.hour.ago)

    assert_no_enqueued_jobs(only: AttemptCodeCheckJob) do
      AttemptRecheckJob.perform_now
    end
  end

  test "ignores decided verdicts" do
    attempt = Attempt.create!(question: @question, user: @user,
      body: "def solve(x):\n  return x", language: "python")
    attempt.update_columns(verdict: "correct", updated_at: 1.hour.ago)

    assert_no_enqueued_jobs(only: AttemptCodeCheckJob) do
      AttemptRecheckJob.perform_now
    end
  end

  test "ignores checked-but-pending attempts" do
    attempt = Attempt.create!(question: @question, user: @user,
      body: "def solve(x):\n  return x", language: "python")
    attempt.update_columns(code_total: 10, code_passed: 5,
      code_needs_review: true, updated_at: 1.hour.ago)

    assert_no_enqueued_jobs(only: AttemptCodeCheckJob) do
      AttemptRecheckJob.perform_now
    end
  end
end
