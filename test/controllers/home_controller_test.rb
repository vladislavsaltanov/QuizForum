require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "guest is redirected to sign in" do
    get root_path

    assert_redirected_to new_session_path
  end

  test "shows nav, hero, search, filters, cards and sign out" do
    user = users(:one)
    sign_in_as(user)
    get root_path

    assert_response :success
    assert_select ".qf-logo", text: "QuizForum"
    assert_select ".qf-nav-item", text: "Главный экран"
    assert_select ".qf-nav-item", text: "Мои вопросы"
    assert_select ".qf-nav-item", text: "Таблица лидеров"
    assert_select ".qf-nav-item", text: "Профиль"
    assert_select ".qf-kicker", text: /Открытые вопросы/
    assert_select "h1.qf-hero", text: "Вопросы"
    assert_select "input[name=q]"
    assert_select "select[name=author]"
    assert_select "select[name=difficulty]"
    assert_select "select[name=topic]"
    assert_select ".qf-card", count: 5
    assert_select ".qf-card-num", text: "01"
    assert_select ".qf-card-title", text: /подстроки/
    assert_select ".qf-card-attempts", text: /ответили:/
    assert_select ".qf-chip", text: /до /
    assert_select ".qf-card-link[href=?]", question_path(questions(:open_text))
    assert_select ".qf-footer"
    assert_select ".qf-user-email", text: user.email
    assert_select "form[action=?]", session_path do
      assert_select "button", text: "Выйти"
    end
  end

  test "filters questions by search text and difficulty" do
    user = users(:one)
    sign_in_as(user)
    get root_path, params: { q: "подстроки", difficulty: "среднее" }

    assert_response :success
    assert_select ".qf-card", count: 1
    assert_select ".qf-card-title", text: /подстроки/
  end
end
