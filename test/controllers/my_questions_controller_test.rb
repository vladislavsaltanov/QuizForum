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

  test "trustee section hidden when no grants" do
    get my_questions_path

    assert_response :success
    assert_select "hr.qf-divider", count: 0
    assert_select "section[aria-label='Наблюдаемые вопросы']", count: 0
  end

  test "revoked grant disappears from trustee section" do
    other = questions(:closed_text)
    grant = other.question_trustees.create!(user: @user)
    grant.destroy!
    get my_questions_path

    assert_select "section[aria-label='Наблюдаемые вопросы'] .qf-card", count: 0
  end

  test "own questions are paged by 20 under a pager" do
    22.times { |i| own_question("Свои #{i}") }

    get my_questions_path
    assert_select "section[aria-label='Мои вопросы'] .qf-card", count: 20
    assert_select "section[aria-label='Мои вопросы'] + .qf-pager a[href*='page=2']", minimum: 1

    get my_questions_path, params: { page: 2 }
    assert_select "section[aria-label='Мои вопросы'] .qf-card", count: 5
  end

  test "trustee questions get their own page key" do
    22.times do |i|
      observed = Question.create!(title: "Наблюдаемый #{i}", body: "Тело", answer_type: "text",
                                 reference_answer: "Ответ", deadline: 7.days.from_now, author: users(:two))
      observed.question_trustees.create!(user: @user)
    end

    get my_questions_path
    assert_select "section[aria-label='Наблюдаемые вопросы'] .qf-card", count: 20
    assert_select "section[aria-label='Наблюдаемые вопросы'] + .qf-pager a[href*='t_page=2']", minimum: 1

    get my_questions_path, params: { t_page: 2 }
    assert_select "section[aria-label='Наблюдаемые вопросы'] .qf-card", count: 2
  end

  test "empty state for fresh user" do
    fresh = User.create!(name: "Fresh", email: "fresh@example.com",
                         password: "password12345678", password_confirmation: "password12345678")
    sign_in_as(fresh)
    get my_questions_path

    assert_select ".qf-card", count: 0
    assert_select ".qf-empty", text: /ничего не опубликовали/
  end

  private
    def own_question(title)
      Question.create!(title: title, body: "Тело", answer_type: "text",
                       reference_answer: "Ответ", deadline: 7.days.from_now, author: @user)
    end
end
