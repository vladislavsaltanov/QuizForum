require "test_helper"

class QuestionsInTestTest < ActionDispatch::IntegrationTest
  setup do
    @author = users(:one)
    @stranger = users(:two)
    @test = @author.authored_tests.create!(title: "Мидтерм", deadline: 3.days.from_now, published: true)
  end

  test "author opens the bound question form for their test" do
    sign_in_as(@author)

    get new_question_path(test_id: @test.id)

    assert_response :success
    assert_select "input[type=hidden][name='question[test_id]'][value=?]", @test.id.to_s
  end

  test "stranger cannot add a question to another author's test" do
    sign_in_as(@stranger)

    get new_question_path(test_id: @test.id)
    assert_redirected_to test_path(@test)
    assert_match(/Только автор теста/, flash[:alert].to_s)

    post questions_path, params: { question: { test_id: @test.id, title: "Чужой", body: "b",
      answer_type: "text", reference_answer: "r" } }
    assert_redirected_to test_path(@test)
    assert_equal 0, @test.questions.count
  end

  test "author adds a choice question to the test through the bound form" do
    sign_in_as(@author)

    assert_difference("@test.questions.count", 1) do
      post questions_path, params: { question: { test_id: @test.id, title: "Сколько?", body: "b",
        answer_type: "single_choice", reference_answer: "",
        options_text: [ "4", "5" ], options_correct: [ "0" ] } }
    end

    assert_redirected_to edit_test_path(@test)
  end

  test "author edits a test question and returns to the manage screen" do
    question = @test.questions.create!(title: "q", body: "b", answer_type: "text",
      reference_answer: "r", deadline: @test.deadline, author: @author, points: 2, position: 0)
    sign_in_as(@author)

    patch question_path(question), params: { question: { title: "Правка", body: "b2",
      answer_type: "text", reference_answer: "r2" } }

    assert_redirected_to edit_test_path(@test)
    assert_equal "Правка", question.reload.title
  end

  test "trustee list syncs on edit when the form sends the field" do
    question = @test.questions.create!(title: "q", body: "b", answer_type: "text",
      reference_answer: "r", deadline: @test.deadline, author: @author, points: 2, position: 0)
    sign_in_as(@author)

    patch question_path(question), params: { question: { title: "q", body: "b",
      answer_type: "text", reference_answer: "r", trustee_emails: "two@example.com" } }

    assert_redirected_to edit_test_path(@test)
    assert_equal [ users(:two) ], question.reload.trustees.to_a
  end

  test "invalid standalone question rerenders the form with errors" do
    sign_in_as(@author)

    assert_no_difference("Question.count") do
      post questions_path, params: { question: { title: "", body: "b",
        answer_type: "text", reference_answer: "r" } }
    end

    assert_response :unprocessable_entity
  end
end
