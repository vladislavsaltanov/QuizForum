require "test_helper"

class AdminAccessTest < ActionDispatch::IntegrationTest
  setup do
    @author = users(:one)
    @respondent = users(:two)
    @admin = User.create!(name: "Admin", email: "admin@example.com",
      password: "password12345678", password_confirmation: "password12345678",
      admin: true, display_role: "администратор")
    @question = questions(:open_text)
  end

  test "admin sees чужые ответы и reference до дедлайна" do
    Attempt.create!(question: @question, user: @respondent, body: "secret-answer")
    sign_in_as(@admin)
    get question_path(@question)

    assert_response :success
    assert_match(/secret-answer/, response.body)
    assert_match(/префикс-функцию/, response.body)
  end

  test "чужой без прав не видит текстов" do
    Attempt.create!(question: @question, user: @respondent, body: "secret-answer")
    stranger = User.create!(name: "Stranger", email: "stranger-x@example.com",
      password: "password12345678", password_confirmation: "password12345678")
    sign_in_as(stranger)
    get question_path(@question)

    assert_response :success
    assert_no_match(/secret-answer/, response.body)
  end

  test "admin аппрувит чужие комменты" do
    comment = Comment.create!(question: @question, user: @respondent, body: "publish me")
    sign_in_as(@admin)
    patch approve_question_comment_path(@question, comment)

    assert_redirected_to question_path(@question, tab: "comments")
    assert_equal "approved", comment.reload.status
  end

  test "admin правит чужой вопрос, чужой получает 403" do
    sign_in_as(@admin)
    get edit_question_path(@question)

    assert_response :success

    patch question_path(@question), params: { question: {
      title: "Отредактировано админом", body: @question.body, answer_type: "text",
      deadline: @question.deadline, reference_answer: @question.reference_answer,
      tags_string: "тест" } }

    assert_redirected_to question_path(@question)
    assert_equal "Отредактировано админом", @question.reload.title

    stranger = User.create!(name: "Stranger2", email: "stranger2@example.com",
      password: "password12345678", password_confirmation: "password12345678")
    sign_in_as(stranger)
    get edit_question_path(@question)

    assert_response :forbidden
    patch question_path(@question), params: { question: {
      title: "Хак", body: @question.body, answer_type: "text",
      deadline: @question.deadline, reference_answer: @question.reference_answer } }

    assert_response :forbidden
  end

  test "admin удаляет чужой вопрос, чужой получает 403" do
    q = Question.create!(title: "t-del", body: "b", answer_type: "text",
      reference_answer: "r", deadline: 7.days.from_now, author: @author, tags: [])
    stranger = User.create!(name: "Stranger3", email: "stranger3@example.com",
      password: "password12345678", password_confirmation: "password12345678")
    sign_in_as(stranger)
    delete question_path(q)

    assert_response :forbidden

    sign_in_as(@admin)
    delete question_path(q)

    assert_redirected_to root_path
    assert_nil Question.find_by(id: q.id)
  end

  test "массовое назначение admin через регистрацию и профиль отбрасывается" do
    sign_out
    post registrations_path, params: { user: { name: "Evil", email: "evil-x@example.com",
      password: "password12345678", password_confirmation: "password12345678", admin: true } }

    assert_equal false, User.find_by(email: "evil-x@example.com")&.admin?

    sign_in_as(@respondent)
    patch profile_path, params: { user: { name: "Two", admin: true } }

    assert_equal false, @respondent.reload.admin?
  end

  test "инъекция через question params не меняет admin" do
    sign_in_as(@admin)
    patch question_path(@question), params: { question: {
      title: @question.title, body: @question.body, answer_type: "text",
      deadline: @question.deadline, reference_answer: @question.reference_answer,
      admin: true } }

    assert_redirected_to question_path(@question)
    assert_equal false, @respondent.reload.admin?
  end
end
