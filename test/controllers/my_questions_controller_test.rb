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

  test "trustee questions appear after divider with author name" do
    other = questions(:closed_text) # author: users(:two)
    other.question_trustees.create!(user: @user)
    get my_questions_path

    assert_response :success
    assert_select "hr.qf-divider", count: 1
    assert_select "section[aria-label='Наблюдаемые вопросы'] .qf-card-title", text: other.title
    assert_select "section[aria-label='Наблюдаемые вопросы'] .qf-card-author", text: "Two"
    assert_select "section[aria-label='Наблюдаемые вопросы'] .qf-card-link[href=?]", question_path(other)
  end

  test "trustee empty state when no grants" do
    get my_questions_path

    assert_response :success
    assert_select "section[aria-label='Наблюдаемые вопросы'] .qf-empty", text: /не назначили наблюдателем/
  end

  test "revoked grant disappears from trustee section" do
    other = questions(:closed_text)
    grant = other.question_trustees.create!(user: @user)
    grant.destroy!
    get my_questions_path

    assert_select "section[aria-label='Наблюдаемые вопросы'] .qf-card", count: 0
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
