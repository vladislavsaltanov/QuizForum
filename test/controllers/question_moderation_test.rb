require "test_helper"

class QuestionModerationTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "toxic question is rejected and never saved" do
    with_verdict(:reject, "оскорбление") do
      assert_no_difference("Question.count") do
        post questions_path, params: { question: {
          title: "Токсичный заголовок", body: "Токсичное условие", answer_type: "text",
          deadline: "2030-01-01T12:00", reference_answer: "Ответ"
        } }
      end
    end

    assert_response :unprocessable_entity
    assert_select ".qf-alert", text: /Отклонено/
  end

  test "sidecar timeout keeps nothing and shows reason" do
    with_verdict(:try_later, "недоступна") do
      assert_no_difference("Question.count") do
        post questions_path, params: { question: {
          title: "Мирный вопрос", body: "Мирное условие", answer_type: "text",
          deadline: "2030-01-01T12:00", reference_answer: "Ответ"
        } }
      end
    end

    assert_response :unprocessable_entity
    assert_select ".qf-alert", text: /не удалась/
  end

  test "toxic edit is rejected and keeps old text" do
    q = questions(:open_text)
    with_verdict(:reject, "оскорбление") do
      patch question_path(q), params: { question: {
        title: "Токсичный", body: q.body, answer_type: "text",
        deadline: q.deadline.strftime("%Y-%m-%dT%H:%M"), reference_answer: q.reference_answer
      } }
    end

    assert_response :unprocessable_entity
    assert_not_equal "Токсичный", q.reload.title
  end
end
