require "test_helper"

class TrusteeGrantsTest < ActionDispatch::IntegrationTest
  setup do
    @question = questions(:open_text) # author: users(:one), open
    @author = users(:one)
    @candidate = users(:two)
  end

  test "author grants trustee by email" do
    sign_in_as(@author)
    post question_trustees_path(@question), params: { email: @candidate.email }

    assert_redirected_to question_path(@question)
    assert @question.trustees.exists?(@candidate.id)
  end

  test "grant to unknown email fails with alert" do
    sign_in_as(@author)
    post question_trustees_path(@question), params: { email: "ghost@example.com" }

    assert_redirected_to question_path(@question)
    assert_match(/не найден/, flash[:alert])
    assert_equal 0, @question.question_trustees.count
  end

  test "grant to author fails" do
    sign_in_as(@author)
    post question_trustees_path(@question), params: { email: @author.email }

    assert_redirected_to question_path(@question)
    assert_equal 0, @question.question_trustees.count
  end

  test "trustee cannot grant others" do
    @question.question_trustees.create!(user: @candidate)
    outsider = User.create!(name: "Out", email: "out@example.com", password: "0123456789ab")
    sign_in_as(@candidate)
    post question_trustees_path(@question), params: { email: outsider.email }

    assert_response :forbidden
    assert_equal 1, @question.question_trustees.count
  end

  test "outsider cannot grant" do
    outsider = User.create!(name: "Out", email: "out@example.com", password: "0123456789ab")
    sign_in_as(outsider)
    post question_trustees_path(@question), params: { email: @candidate.email }

    assert_response :forbidden
    assert_equal 0, @question.question_trustees.count
  end

  test "author revokes trustee; revoked trustee blind again" do
    grant = @question.question_trustees.create!(user: @candidate)
    Attempt.create!(question: @question, user: @author, body: "sekret-text")
    sign_in_as(@author)
    delete question_trustee_path(@question, grant)

    assert_redirected_to question_path(@question)
    assert_equal 0, @question.question_trustees.count

    sign_in_as(@candidate)
    get question_path(@question)

    assert_no_match(/sekret-text/, response.body)
  end

  test "trustee cannot revoke" do
    grant = @question.question_trustees.create!(user: @candidate)
    sign_in_as(@candidate)
    delete question_trustee_path(@question, grant)

    assert_response :forbidden
    assert_equal 1, @question.question_trustees.count
  end

  test "management block hidden from trustee" do
    @question.question_trustees.create!(user: @candidate)
    sign_in_as(@candidate)
    get question_path(@question)

    assert_response :success
    assert_no_match(/Наблюдатели/, response.body)
  end

  test "create with trustee email grants" do
    sign_in_as(@author)
    post questions_path, params: {
      question: {
        title: "Новый вопрос", body: "Текст", answer_type: "text",
        deadline: 7.days.from_now.strftime("%Y-%m-%dT%H:%M"),
        reference_answer: "Эталон", trustee_email: @candidate.email
      }
    }

    q = Question.find_by!(title: "Новый вопрос")
    assert_redirected_to question_path(q)
    assert q.trustees.exists?(@candidate.id)
  end

  test "create with unknown trustee email still saves question with alert" do
    sign_in_as(@author)
    post questions_path, params: {
      question: {
        title: "Вопрос без наблюдателя", body: "Текст", answer_type: "text",
        deadline: 7.days.from_now.strftime("%Y-%m-%dT%H:%M"),
        reference_answer: "Эталон", trustee_email: "ghost@example.com"
      }
    }

    q = Question.find_by!(title: "Вопрос без наблюдателя")
    assert_redirected_to question_path(q)
    assert_match(/не найден/, flash[:alert])
    assert_equal 0, q.question_trustees.count
  end

  test "update with trustee email grants" do
    sign_in_as(@author)
    patch question_path(@question), params: {
      question: {
        title: @question.title, body: @question.body, answer_type: "text",
        deadline: @question.deadline.strftime("%Y-%m-%dT%H:%M"),
        reference_answer: @question.reference_answer, trustee_email: @candidate.email
      }
    }

    assert_redirected_to question_path(@question)
    assert @question.trustees.exists?(@candidate.id)
  end

  test "update with own email grants nothing and alerts" do
    sign_in_as(@author)
    patch question_path(@question), params: {
      question: {
        title: @question.title, body: @question.body, answer_type: "text",
        deadline: @question.deadline.strftime("%Y-%m-%dT%H:%M"),
        reference_answer: @question.reference_answer, trustee_email: @author.email
      }
    }

    assert_redirected_to question_path(@question)
    assert_not_nil flash[:alert]
    assert_equal 0, @question.question_trustees.count
  end
end
