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

  test "visible_for shows approved plus own comments to a stranger" do
    approved = comment_for(users(:two), "виден")
    mine = comment_for(users(:two), "мой")
    hidden = comment_for(users(:one), "чужой")
    approved.update_column(:status, "approved")

    visible = Comment.visible_for(questions(:open_text), users(:two)).pluck(:id)

    assert_includes visible, approved.id
    assert_includes visible, mine.id
    assert_not_includes visible, hidden.id
  end

  test "visible_for shows every status to the question author" do
    pending = comment_for(users(:two), "авторский")

    assert_includes Comment.visible_for(questions(:open_text), users(:one)).pluck(:id), pending.id
  end

  private
    def comment_for(user, body)
      Comment.create!(question: questions(:open_text), user: user, body: body)
    end
end
