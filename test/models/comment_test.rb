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

  test "visible_live? on a test comment ignores the question branch" do
    test = users(:one).authored_tests.create!(title: "Т", deadline: 1.day.from_now)
    pending = test.comments.create!(user: users(:two), body: "ждёт")
    approved = test.comments.create!(user: users(:two), body: "ок", status: "approved")

    assert_not pending.visible_live?
    assert approved.visible_live?
  end

  test "comment belongs to exactly one of question or test" do
    neither = Comment.new(user: users(:one), body: "бездомный")
    both = Comment.new(user: users(:one), body: "жадный", question: questions(:open_text),
      test: users(:two).authored_tests.create!(title: "T", deadline: 1.day.from_now))

    assert_not neither.valid?
    assert_not both.valid?
    assert both.errors[:base].any?
  end

  private
    def comment_for(user, body)
      Comment.create!(question: questions(:open_text), user: user, body: body)
    end
end
