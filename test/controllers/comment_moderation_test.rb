require "test_helper"

class CommentModerationTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:two)
    @question = questions(:open_text)
    sign_in_as(@user)
  end

  test "toxic comment is rejected and never saved" do
    with_verdict(:reject, "оскорбление") do
      assert_no_difference("Comment.count") do
        post question_comments_path(@question), params: { comment: { body: "токсичный текст" } }
      end
    end

    assert_redirected_to question_path(@question, tab: "comments")
  end

  test "pass comment publishes immediately" do
    with_verdict(:pass) do
      post question_comments_path(@question), params: { comment: { body: "мирный вопрос" } }
    end

    assert_equal "approved", @question.comments.find_by(user: @user).status
  end

  test "sidecar timeout keeps nothing and asks to retry" do
    with_verdict(:try_later, "недоступна") do
      assert_no_difference("Comment.count") do
        post question_comments_path(@question), params: { comment: { body: "мирный вопрос" } }
      end
    end

    assert_redirected_to question_path(@question, tab: "comments")
    follow_redirect!
    assert_select ".qf-alert", text: /не удалась/
  end

  test "review verdict still saves as pending" do
    with_verdict(:review, "на проверке") do
      assert_difference("Comment.count", 1) do
        post question_comments_path(@question), params: { comment: { body: "спорный вопрос" } }
      end
    end

    assert_equal "pending", @question.comments.find_by(user: @user).status
  end
end
