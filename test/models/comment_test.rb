require "test_helper"

class CommentTest < ActiveSupport::TestCase
  test "requires body" do
    comment = Comment.new(question: questions(:open_text), user: users(:one), body: "")

    assert_not comment.valid?
  end

  test "rejects body over 2000 chars" do
    comment = Comment.new(question: questions(:open_text), user: users(:one), body: "x" * 2001)

    assert_not comment.valid?
  end

  test "rejects unknown status" do
    comment = Comment.new(question: questions(:open_text), user: users(:one), body: "уточните условие", status: "archived")

    assert_not comment.valid?
  end

  test "approved reflects status" do
    assert Comment.new(question: questions(:open_text), user: users(:one), body: "ок", status: "approved").approved?
    assert_not Comment.new(question: questions(:open_text), user: users(:one), body: "ок", status: "pending").approved?
  end
end
