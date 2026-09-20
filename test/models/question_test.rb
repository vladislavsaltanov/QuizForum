require "test_helper"

class QuestionTest < ActiveSupport::TestCase
  setup do
    @author = users(:one)
  end

  test "drops blank option rows before grading" do
    q = Question.create!(title: "t", body: "b", answer_type: "single_choice",
      options: [ { "text" => "a", "correct" => true }, { "text" => "  ", "correct" => false }, { "text" => "b", "correct" => false } ],
      reference_answer: "r", deadline: 7.days.from_now, author: @author, tags: [])

    assert_equal [ "a", "b" ], q.options.map { |o| o["text"] }
  end

  test "rejects more than six options" do
    opts = 7.times.map { |i| { "text" => "o#{i}", "correct" => i.zero? } }
    q = Question.new(title: "t", body: "b", answer_type: "single_choice", options: opts,
      reference_answer: "r", deadline: 7.days.from_now, author: @author, tags: [])

    assert_not q.valid?
  end

  test "rejects multiple choice without correct option" do
    q = Question.new(title: "t", body: "b", answer_type: "multiple_choice",
      options: [ { "text" => "a", "correct" => false }, { "text" => "b", "correct" => false } ],
      reference_answer: "r", deadline: 7.days.from_now, author: @author, tags: [])

    assert_not q.valid?
  end
end
