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

  test "filters questions by author" do
    user = users(:one)
    sign_in_as(user)
    get root_path, params: { author: "Two" }

    assert_response :success
    assert_select ".qf-card", count: 2
  end

  test "filters questions by topic" do
    user = users(:one)
    sign_in_as(user)
    get root_path, params: { topic: "протоколы" }

    assert_response :success
    assert_select ".qf-card", count: 1
    assert_select ".qf-card-title", text: /TCP/
  end

  test "splits the index into pages of 20 questions" do
    40.times { |i| bulk_question("Массовый #{i}") }
    sign_in_as(users(:one))

    get root_path
    assert_select ".qf-card", count: 20
    assert_select ".qf-kicker", text: /Открытые вопросы · 45/

    get root_path, params: { page: 2 }
    assert_select ".qf-card", count: 20

    get root_path, params: { page: 3 }
    assert_select ".qf-card", count: 5
  end

  test "pager sits under the cards and keeps the active filters" do
    25.times { |i| bulk_question("Массовый #{i}") }
    sign_in_as(users(:one))
    get root_path, params: { difficulty: "среднее" }

    assert_select ".qf-cards + .qf-pager" do
      assert_select "a[href*='page=2']", minimum: 1
      assert_select "a[href*='difficulty=%D1%81%D1%80%D0%B5%D0%B4%D0%BD%D0%B5%D0%B5']", minimum: 1
    end
  end

  test "pager marks the current page and clamps a page past the last one" do
    25.times { |i| bulk_question("Массовый #{i}") }
    sign_in_as(users(:one))
    get root_path, params: { page: 99 }

    assert_response :success
    assert_select ".qf-card", count: 10
    assert_select ".qf-pager [aria-current=page]", text: "2"
  end

  test "single page of results renders no pager" do
    sign_in_as(users(:one))
    get root_path, params: { q: "подстроки" }

    assert_select ".qf-card", count: 1
    assert_select ".qf-pager", count: 0
  end

  private
    def bulk_question(title)
      Question.create!(title: title, body: "Тело", answer_type: "text",
                       reference_answer: "Ответ", deadline: 7.days.from_now,
                       author: users(:one), tags: [ "среднее" ])
    end
end
