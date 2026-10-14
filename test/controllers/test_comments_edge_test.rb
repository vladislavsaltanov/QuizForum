require "test_helper"

class TestCommentsEdgeTest < ActionDispatch::IntegrationTest
  TURBO = "text/vnd.turbo-stream.html"

  setup do
    @author = users(:one)
    @poster = users(:two)
    @test = @author.authored_tests.create!(title: "Обсуждаемый", deadline: 1.day.from_now, published: true)
  end

  test "comments on a draft bounce with an alert" do
    sign_in_as(@author)
    draft = @author.authored_tests.create!(title: "Дра", deadline: 1.day.from_now)

    post test_comments_path(draft), params: { comment: { body: "рано" } }

    assert_redirected_to test_path(draft)
    assert_match(/ещё не опубликован/, flash[:alert].to_s)
    assert_equal 0, draft.comments.count
  end

  test "empty comment body is rejected" do
    sign_in_as(@poster)

    assert_no_difference("Comment.count") do
      post test_comments_path(@test), params: { comment: { body: "" } }
    end

    assert_redirected_to test_path(@test)
    assert_not_empty flash[:alert].to_s
  end

  test "duplicate body within half a minute is silently dropped" do
    sign_in_as(@poster)
    post test_comments_path(@test), params: { comment: { body: "Дубль" } }
    assert_redirected_to test_path(@test)
    assert_equal 1, @test.comments.count
    assert_nil flash[:alert]

    post test_comments_path(@test), params: { comment: { body: "Дубль" } }
    assert_redirected_to test_path(@test)
    assert_equal 1, @test.comments.count
  end

  test "rejected and unavailable moderation both bounce" do
    sign_in_as(@poster)
    with_verdict(:reject, "спам") do
      assert_no_difference("Comment.count") do
        post test_comments_path(@test), params: { comment: { body: "токсик" } }
      end
    end
    assert_match(/Комментарий отклонён/, flash[:alert].to_s)

    with_verdict(:try_later, "недоступна") do
      assert_no_difference("Comment.count") do
        post test_comments_path(@test), params: { comment: { body: "спокойный" } }
      end
    end
    assert_match(/не удалась/, flash[:alert].to_s)
  end

  test "turbo stream submit of an approved comment only swaps the chatbar" do
    sign_in_as(@poster)

    post test_comments_path(@test), params: { comment: { body: "Из турбо" } },
      headers: { "Accept" => TURBO }

    assert_response :success
    assert_select "turbo-stream[action=replace][target=test-chatbar]", count: 1
    assert_select "turbo-stream[action=append][target=comments]", count: 0
  end

  test "turbo stream submit of a pending comment appends the poster's own bubble" do
    sign_in_as(@poster)
    with_verdict(:flag, "ABUSE") do
      post test_comments_path(@test), params: { comment: { body: "Сомнительный" } },
        headers: { "Accept" => TURBO }
    end

    assert_response :success
    assert_select "turbo-stream[action=append][target=comments] .qf-msg p", text: "Сомнительный"
    assert_select "turbo-stream[action=replace][target=test-chatbar]", count: 1
  end

  test "destroy removes an approved test comment live and recounts" do
    sign_in_as(@poster)
    post test_comments_path(@test), params: { comment: { body: "Норм" } }
    comment = @test.comments.last

    sign_in_as(@author)
    delete test_comment_path(@test, comment)

    assert_redirected_to test_path(@test)
    assert_equal 0, @test.comments.count
  end

  test "destroy of a pending comment on an open test skips the live removal" do
    sign_in_as(@poster)
    with_verdict(:flag, "ABUSE") do
      post test_comments_path(@test), params: { comment: { body: "Ждёт" } }
    end
    pending = @test.comments.find_by(status: "pending")

    sign_in_as(@author)
    delete test_comment_path(@test, pending)

    assert_redirected_to test_path(@test)
    assert_equal 0, @test.comments.count
  end

  test "destroy of an approved question comment removes the live bubble" do
    question = questions(:open_text)
    sign_in_as(@poster)
    post question_comments_path(question), params: { comment: { body: "Норм" } }
    comment = question.comments.find_by(user: @poster)

    sign_in_as(@author)
    delete question_comment_path(question, comment)

    assert_redirected_to question_path(question, tab: "comments")
    assert_equal 0, question.comments.count
  end

  test "question comment index without a cursor serves the newest batch" do
    question = questions(:open_text)
    15.times do |i|
      question.comments.create!(user: @poster, body: "Сообщение #{i}",
        status: "approved", created_at: (20 - i).minutes.ago)
    end
    sign_in_as(@poster)

    get question_comments_path(question), headers: { "Accept" => TURBO }

    assert_response :success
    assert_select "turbo-stream[action=prepend][target=comments] .qf-msg", count: 10
  end
end
