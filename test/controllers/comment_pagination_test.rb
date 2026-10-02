require "test_helper"

class CommentPaginationTest < ActionDispatch::IntegrationTest
  TURBO = "text/vnd.turbo-stream.html"

  setup do
    @question = questions(:open_text) # author: users(:one)
    @viewer = users(:two)
    sign_in_as(@viewer)
  end

  test "guest is redirected to sign in" do
    sign_out
    get question_comments_path(@question)

    assert_redirected_to new_session_path
  end

  test "page shows the 10 newest comments oldest-first with a load marker" do
    seed_comments(25)
    get question_path(@question, tab: "comments")

    assert_response :success
    bodies = css_select("#comments .qf-msg p").map(&:text)
    assert_equal 10, bodies.size
    assert_equal "Комментарий 15", bodies.first
    assert_equal "Комментарий 24", bodies.last
    assert_select "#comments-more[data-before=?]", newest_first_ids[9]
    assert_select ".qf-count", text: /Обсуждение · 25/
  end

  test "no marker when everything already fits on screen" do
    seed_comments(3)
    get question_path(@question, tab: "comments")

    assert_select "#comments .qf-msg", count: 3
    assert_select "#comments-more", count: 0
  end

  test "index prepends the next 10 older comments" do
    seed_comments(25)
    get question_comments_path(@question), params: { before: newest_first_ids[9] },
      headers: { "Accept" => TURBO }

    assert_response :success
    assert_equal TURBO, response.media_type
    assert_select "turbo-stream[action=prepend][target=comments]" do
      bodies = css_select(".qf-msg p").map(&:text)
      assert_equal "Комментарий 5", bodies.first
      assert_equal "Комментарий 14", bodies.last
    end
  end

  test "index drops the load marker once nothing older is left" do
    seed_comments(12)
    get question_comments_path(@question), params: { before: newest_first_ids[9] },
      headers: { "Accept" => TURBO }

    assert_select "turbo-stream[action=prepend][target=comments] .qf-msg", count: 2
    assert_select "turbo-stream[action=remove][target=comments-more]"
  end

  test "index keeps another user's pending comment hidden" do
    @question.comments.create!(user: users(:one), body: "Чужой pending", status: "pending")
    seed_comments(11)
    get question_comments_path(@question), params: { before: newest_first_ids[9] },
      headers: { "Accept" => TURBO }

    assert_response :success
    assert_select "turbo-stream[action=prepend] .qf-msg p", text: "Чужой pending", count: 0
  end

  test "author still sees pending comments in the batch" do
    @question.comments.create!(user: users(:two), body: "Pending от Two", status: "pending")
    seed_comments(4)
    cursor = newest_first_ids[3]
    sign_out
    sign_in_as(users(:one))
    get question_comments_path(@question), params: { before: cursor },
      headers: { "Accept" => TURBO }

    assert_select "turbo-stream[action=prepend] .qf-msg p", text: "Pending от Two"
  end

  test "bad cursor yields an empty batch instead of the whole thread" do
    seed_comments(5)
    get question_comments_path(@question), params: { before: "abc" },
      headers: { "Accept" => TURBO }

    assert_response :success
    assert_select "turbo-stream[action=prepend] .qf-msg", count: 0
  end

  test "plain html request to the cursor endpoint gets nothing" do
    seed_comments(15)
    get question_comments_path(@question), params: { before: newest_first_ids[9] }

    assert_response :no_content
  end

  private
    def seed_comments(count)
      count.times do |i|
        @question.comments.create!(user: users(:two), body: "Комментарий #{i}",
          status: "approved", created_at: (count - i).minutes.ago)
      end
    end

    def newest_first_ids
      @question.comments.order(created_at: :desc, id: :desc).pluck(:id)
    end
end
