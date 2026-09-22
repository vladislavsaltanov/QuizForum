require "test_helper"

class TrusteeGrantsTest < ActionDispatch::IntegrationTest
  setup do
    @question = questions(:open_text) # author: users(:one), open
    @author = users(:one)
    @candidate = users(:two)
  end

  test "create with comma-separated emails grants all" do
    other = User.create!(name: "Other", email: "other@example.com", password: "0123456789ab")
    sign_in_as(@author)
    post questions_path, params: {
      question: {
        title: "Новый вопрос", body: "Текст", answer_type: "text",
        deadline: 7.days.from_now.strftime("%Y-%m-%dT%H:%M"),
        reference_answer: "Эталон", trustee_emails: "#{@candidate.email}, #{other.email}"
      }
    }

    q = Question.find_by!(title: "Новый вопрос")
    assert_redirected_to question_path(q)
    assert q.trustees.exists?(@candidate.id)
    assert q.trustees.exists?(other.id)
  end

  test "create with unknown email in list saves question, grants known, alerts" do
    sign_in_as(@author)
    post questions_path, params: {
      question: {
        title: "Вопрос частично", body: "Текст", answer_type: "text",
        deadline: 7.days.from_now.strftime("%Y-%m-%dT%H:%M"),
        reference_answer: "Эталон", trustee_emails: "#{@candidate.email}, ghost@example.com"
      }
    }

    q = Question.find_by!(title: "Вопрос частично")
    assert_redirected_to question_path(q)
    assert q.trustees.exists?(@candidate.id)
    assert_match(/ghost@example.com/, flash[:alert])
  end

  test "update replaces set: removing email revokes" do
    other = User.create!(name: "Other", email: "other@example.com", password: "0123456789ab")
    @question.question_trustees.create!(user: @candidate)
    sign_in_as(@author)
    patch question_path(@question), params: {
      question: {
        title: @question.title, body: @question.body, answer_type: "text",
        deadline: @question.deadline.strftime("%Y-%m-%dT%H:%M"),
        reference_answer: @question.reference_answer, trustee_emails: other.email
      }
    }

    assert_redirected_to question_path(@question)
    assert_not @question.trustees.exists?(@candidate.id)
    assert @question.trustees.exists?(other.id)
  end

  test "update with blank field clears all" do
    @question.question_trustees.create!(user: @candidate)
    sign_in_as(@author)
    patch question_path(@question), params: {
      question: {
        title: @question.title, body: @question.body, answer_type: "text",
        deadline: @question.deadline.strftime("%Y-%m-%dT%H:%M"),
        reference_answer: @question.reference_answer, trustee_emails: ""
      }
    }

    assert_redirected_to question_path(@question)
    assert_equal 0, @question.question_trustees.count
  end

  test "update with own email grants nothing and alerts" do
    sign_in_as(@author)
    patch question_path(@question), params: {
      question: {
        title: @question.title, body: @question.body, answer_type: "text",
        deadline: @question.deadline.strftime("%Y-%m-%dT%H:%M"),
        reference_answer: @question.reference_answer, trustee_emails: @author.email
      }
    }

    assert_redirected_to question_path(@question)
    assert_not_nil flash[:alert]
    assert_equal 0, @question.question_trustees.count
  end

  test "trustee editing question cannot change set" do
    other = User.create!(name: "Other", email: "other@example.com", password: "0123456789ab")
    @question.question_trustees.create!(user: @candidate)
    sign_in_as(@candidate)
    patch question_path(@question), params: {
      question: {
        title: @question.title, body: @question.body, answer_type: "text",
        deadline: @question.deadline.strftime("%Y-%m-%dT%H:%M"),
        reference_answer: @question.reference_answer, trustee_emails: other.email
      }
    }

    assert_redirected_to question_path(@question)
    assert @question.trustees.exists?(@candidate.id)
    assert_not @question.trustees.exists?(other.id)
  end

  test "edit form shows field prefilled with current emails" do
    @question.question_trustees.create!(user: @candidate)
    sign_in_as(@author)
    get edit_question_path(@question)

    assert_response :success
    assert_match(/Наблюдатели/, response.body)
    assert_match(/#{@candidate.email}/, response.body)
  end

  test "show page has no management block" do
    @question.question_trustees.create!(user: @candidate)
    sign_in_as(@author)
    get question_path(@question)

    assert_response :success
    assert_no_match(/Наблюдатели/, response.body)
    assert_no_match(/Отозвать/, response.body)
  end
end
