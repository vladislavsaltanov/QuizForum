require "test_helper"

class AttemptsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @question = questions(:open_text)
    @author = users(:one)
    @respondent = users(:two)
  end

  test "text create enqueues jury job" do
    sign_in_as(@respondent)
    assert_enqueued_with(job: AttemptJuryJob) do
      post question_attempts_path(@question), params: { attempt: { body: "Развёрнутый ответ" } }
    end

    assert_redirected_to question_path(@question)
  end

  test "choice create does not enqueue" do
    q = @author.authored_questions.create!(title: "Выбор", body: "Тело",
      answer_type: "single_choice", deadline: 7.days.from_now,
      options: [ { "text" => "да", "correct" => true }, { "text" => "нет", "correct" => false } ])
    sign_in_as(@respondent)
    assert_no_enqueued_jobs only: AttemptJuryJob do
      post question_attempts_path(q), params: { attempt: { selected: [ "0" ] } }
    end

    assert_redirected_to question_path(q)
  end

  test "stranger cannot set verdict" do
    attempt = attempt_by(@respondent)
    sign_in_as(User.create!(name: "Stranger", email: "stranger@example.com", password: "0123456789ab"))
    patch verdict_question_attempt_path(@question, attempt), params: { attempt: { verdict: "correct" } }

    assert_response :forbidden
    assert_equal "pending", attempt.reload.verdict
  end

  test "respondent cannot set own verdict" do
    attempt = attempt_by(@respondent)
    sign_in_as(@respondent)
    patch verdict_question_attempt_path(@question, attempt), params: { attempt: { verdict: "correct" } }

    assert_response :forbidden
    assert_equal "pending", attempt.reload.verdict
  end

  test "author sets and changes any verdict" do
    attempt = attempt_by(@respondent)
    sign_in_as(@author)
    patch verdict_question_attempt_path(@question, attempt), params: { attempt: { verdict: "incorrect" } }

    assert_redirected_to question_path(@question)
    assert_equal "incorrect", attempt.reload.verdict

    patch verdict_question_attempt_path(@question, attempt), params: { attempt: { verdict: "correct" } }

    assert_equal "correct", attempt.reload.verdict
  end

  test "trustee sets verdict" do
    attempt = attempt_by(@respondent)
    @question.question_trustees.create!(user: @respondent)
    other = User.create!(name: "Other", email: "other@example.com", password: "0123456789ab")
    attempt2 = attempt_by(other)
    sign_in_as(@respondent)
    patch verdict_question_attempt_path(@question, attempt2), params: { attempt: { verdict: "partial" } }

    assert_redirected_to question_path(@question)
    assert_equal "partial", attempt2.reload.verdict
  end

  test "admin sets verdict" do
    attempt = attempt_by(@respondent)
    admin = User.create!(name: "Admin", email: "admin@example.com", password: "0123456789ab", admin: true)
    sign_in_as(admin)
    patch verdict_question_attempt_path(@question, attempt), params: { attempt: { verdict: "correct" } }

    assert_redirected_to question_path(@question)
    assert_equal "correct", attempt.reload.verdict
  end

  test "unknown verdict is rejected" do
    attempt = attempt_by(@respondent)
    sign_in_as(@author)
    patch verdict_question_attempt_path(@question, attempt), params: { attempt: { verdict: "brilliant" } }

    assert_response :bad_request
    assert_equal "pending", attempt.reload.verdict
  end

  test "tampered question id is not found" do
    attempt = attempt_by(@respondent)
    other = @author.authored_questions.create!(title: "Чужой", body: "Тело",
      answer_type: "text", deadline: 7.days.from_now, reference_answer: "Эталон")
    sign_in_as(@author)
    patch verdict_question_attempt_path(other, attempt), params: { attempt: { verdict: "correct" } }

    assert_response :not_found
    assert_equal "pending", attempt.reload.verdict
  end

  test "author regrade enqueues job" do
    attempt = attempt_by(@respondent)
    sign_in_as(@author)
    assert_enqueued_with(job: AttemptJuryJob) do
      post regrade_question_attempt_path(@question, attempt)
    end

    assert_redirected_to question_path(@question)
  end

  test "stranger cannot regrade" do
    attempt = attempt_by(@respondent)
    sign_in_as(User.create!(name: "Stranger", email: "stranger2@example.com", password: "0123456789ab"))
    assert_no_enqueued_jobs only: AttemptJuryJob do
      post regrade_question_attempt_path(@question, attempt)
    end

    assert_response :forbidden
  end

  test "author page shows jury suggestion and buttons" do
    attempt_by(@respondent, jury_label: "partial", jury_score: 0.5,
      jury_needs_review: true, jury_reasons: "покрыта часть пунктов")
    sign_in_as(@author)
    get question_path(@question)

    assert_response :success
    assert_match(/Подсказка/, response.body)
    assert_match(/покрыта часть пунктов/, response.body)
    assert_match(/Переоценить/, response.body)
  end

  test "author sees real verdict chip instead of pending" do
    attempt_by(@respondent, verdict: "incorrect")
    sign_in_as(@author)
    get question_path(@question)

    assert_response :success
    assert_match(/Неправильно/, response.body)
    assert_no_match(/На проверке/, response.body)
  end

  test "author sees buttons even without jury suggestion" do
    attempt_by(@respondent)
    sign_in_as(@author)
    get question_path(@question)

    assert_response :success
    assert_match(/Верно/, response.body)
    assert_match(/Частично/, response.body)
    assert_match(/Неверно/, response.body)
    assert_match(/Переоценить/, response.body)
    assert_no_match(/Подсказка/, response.body)
  end

  test "answers list scrolls like comments" do
    attempt_by(@respondent)
    sign_in_as(@author)
    get question_path(@question)

    assert_select "div.qf-chat", count: 1
  end

  test "stranger page hides jury suggestion" do
    attempt_by(@respondent, jury_label: "partial", jury_score: 0.5,
      jury_needs_review: true, jury_reasons: "покрыта часть пунктов")
    sign_in_as(User.create!(name: "Stranger", email: "stranger3@example.com", password: "0123456789ab"))
    get question_path(@question)

    assert_response :success
    assert_no_match(/Подсказка/, response.body)
  end

  private
    def attempt_by(user, **jury)
      @question.attempts.create!({ user:, body: "Ответ #{user.name}" }.merge(jury))
    end
end
