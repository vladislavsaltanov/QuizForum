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

  private
    # Temporarily replaces the Laya verdict without touching IO.
    def with_verdict(verdict, category)
      ModerationClient.define_singleton_method(:check) do |*_, **_|
        ModerationClient::Result.new(verdict, category)
      end
      yield
    ensure
      ModerationClient.singleton_class.remove_method(:check)
    end
end
