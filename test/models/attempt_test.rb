require "test_helper"

class AttemptTest < ActiveSupport::TestCase
  test "rejects choice attempt without selection" do
    attempt = Attempt.new(question: questions(:closed_single), user: users(:one))

    assert_not attempt.valid?
    assert_includes attempt.errors[:selected], "can't be blank"
  end

  test "rejects code attempt in a language the runner cannot grade" do
    attempt = Attempt.new(question: questions(:closed_single), user: users(:one),
                          selected: [ "1" ], language: "rust")

    assert_not attempt.valid?
    assert attempt.errors[:language].any?
  end

  test "accepts code attempt in a supported language" do
    attempt = Attempt.new(question: questions(:closed_single), user: users(:one),
                          selected: [ "1" ], language: "c#")

    assert attempt.valid?, attempt.errors.full_messages.to_sentence
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

  test "revealed_points narrows by topic tag" do
    tagged = Question.create!(title: "По теме", body: "b", answer_type: "text", reference_answer: "r",
      deadline: 1.day.ago, author: users(:one), tags: %w[среднее topic-xyz-filter])
    other = Question.create!(title: "Мимо темы", body: "b", answer_type: "text", reference_answer: "r",
      deadline: 1.day.ago, author: users(:one), tags: %w[среднее topic-other-filter])
    tagged.attempts.create!(user: users(:two), body: "x", verdict: "correct")
    other.attempts.create!(user: users(:two), body: "x", verdict: "correct")

    board = Attempt.revealed_points(topic: "topic-xyz-filter")

    assert_equal 1, board.size
    assert_equal users(:two), board.first.first
    assert_equal tagged.difficulty_weight, board.first.last
  end
end
