require "test_helper"

class MyQuestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "guest is redirected to sign in" do
    sign_out
    get my_questions_path

    assert_redirected_to new_session_path
  end

  test "lists only own questions with status and links" do
    get my_questions_path

    assert_response :success
    assert_select "h1.qf-hero", text: "Мои вопросы"
    assert_select ".qf-card", count: 3
    assert_select ".qf-card-title", text: "Напишите алгоритм поиска подстроки"
    assert_select ".qf-card-title", text: "Что выведет этот фрагмент на Python?"
    assert_select ".qf-card-title", text: "Объясните разницу между TCP и UDP"
    assert_select ".qf-card-title", { text: "Докажите сходимость метода простых итераций", count: 0 }
    assert_select ".qf-card-author", text: "Открыт"
    assert_select ".qf-card-author", text: "Завершён"
    assert_select ".qf-card-link[href=?]", question_path(questions(:open_text))
  end

  test "empty state for fresh user" do
    fresh = User.create!(name: "Fresh", email: "fresh@example.com",
                         password: "password12345678", password_confirmation: "password12345678")
    sign_in_as(fresh)
    get my_questions_path

    assert_select ".qf-card", count: 0
    assert_select ".qf-empty", text: /ничего не опубликовали/
  end
end
