require "test_helper"

class AttemptTest < ActiveSupport::TestCase
  test "rejects choice attempt without selection" do
    attempt = Attempt.new(question: questions(:closed_single), user: users(:one))

    assert_not attempt.valid?
    assert_includes attempt.errors[:selected], "can't be blank"
  end

  test "rejects out-of-range selected index" do
    attempt = Attempt.new(question: questions(:closed_single), user: users(:one), selected: [ "999" ])

    assert_not attempt.valid?
    assert_includes attempt.errors[:selected], "is not included in the list"
  end

  test "rejects non-numeric selected index" do
    attempt = Attempt.new(question: questions(:closed_single), user: users(:one), selected: [ "abc" ])

    assert_not attempt.valid?
    assert_includes attempt.errors[:selected], "is not included in the list"
  end

  test "rejects body over 8000 chars" do
    attempt = Attempt.new(question: questions(:open_text), user: users(:one), body: "x" * 8001)

    assert_not attempt.valid?
  end

  test "rejects text attempt without body" do
    attempt = Attempt.new(question: questions(:open_text), user: users(:one), body: "")

    assert_not attempt.valid?
  end

  test "grades partial on subset of correct options" do
    attempt = Attempt.create!(question: questions(:closed_multiple), user: users(:one), selected: [ "0" ])

    assert_equal "partial", attempt.verdict
  end
end
