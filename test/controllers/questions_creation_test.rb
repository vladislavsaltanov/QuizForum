require "test_helper"

class QuestionsCreationTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "guest is redirected from new and create" do
    sign_out
    get new_question_path

    assert_redirected_to new_session_path

    post questions_path, params: { question: { title: "x" } }

    assert_redirected_to new_session_path
  end

  test "creates text question with parsed tags" do
    assert_difference "Question.count", 1 do
      post questions_path, params: { question: {
        title: "Новый", body: "Условие", answer_type: "text",
        deadline: "2030-01-01T12:00", reference_answer: "Ответ",
        tags_string: "a, b , c"
      } }
    end

    q = Question.find_by!(title: "Новый")

    assert_equal @user, q.author
    assert_equal %w[a b c], q.tags
    assert_redirected_to question_path(q)
  end

  test "creates single choice with correct flags" do
    post questions_path, params: { question: {
      title: "Выбор", body: "Условие", answer_type: "single_choice",
      deadline: "2030-01-01T12:00", reference_answer: "Ответ",
      options_text: [ "да", "", "нет" ], options_correct: [ "0" ]
    } }

    q = Question.find_by!(title: "Выбор")

    assert_equal [ { "text" => "да", "correct" => true }, { "text" => "нет", "correct" => false } ], q.options
  end

  test "rejects choice without correct answer" do
    assert_no_difference "Question.count" do
      post questions_path, params: { question: {
        title: "Брак", body: "Условие", answer_type: "single_choice",
        deadline: "2030-01-01T12:00", reference_answer: "Ответ",
        options_text: [ "да", "нет" ]
      } }
    end

    assert_response :unprocessable_entity
  end

  test "rejects missing title" do
    assert_no_difference "Question.count" do
      post questions_path, params: { question: {
        title: "", body: "Условие", answer_type: "text",
        deadline: "2030-01-01T12:00", reference_answer: "Ответ"
      } }
    end

    assert_response :unprocessable_entity
  end

  test "rejects single option" do
    assert_no_difference "Question.count" do
      post questions_path, params: { question: {
        title: "Мало", body: "Условие", answer_type: "single_choice",
        deadline: "2030-01-01T12:00", reference_answer: "Ответ",
        options_text: [ "да" ], options_correct: [ "0" ]
      } }
    end

    assert_response :unprocessable_entity
  end
end
