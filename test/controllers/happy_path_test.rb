require "test_helper"

class HappyPathTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "simplest question is created by A and passed by B, then revealed" do
    author = users(:one)
    respondent = users(:two)

    sign_in_as(author)
    assert_difference "Question.count", 1 do
      post questions_path, params: { question: {
        title: "Счастливый путь", body: "Опишите КМП.",
        answer_type: "text", deadline: 1.hour.from_now,
        reference_answer: "Эталон счастливого пути",
        tags_string: "программирование"
      } }
    end
    q = Question.find_by!(title: "Счастливый путь")

    assert_redirected_to question_path(q)

    sign_in_as(respondent)
    assert_enqueued_with(job: AttemptJuryJob) do
      post question_attempts_path(q), params: { attempt: { body: "ответ Б счастливый" } }
    end

    assert_equal "pending", q.attempts.find_by(user: respondent).verdict

    get question_path(q)

    assert_no_match(/Эталон счастливого пути/, response.body)

    travel_to q.deadline + 1.minute do
      get question_path(q)

      assert_response :success
      assert_select "h2", text: "Ответ автора"
      assert_match(/Эталон счастливого пути/, response.body)
      assert_match(/ответ Б счастливый/, response.body)

      sign_in_as(author)
      attempt = q.attempts.find_by!(user: respondent)
      patch verdict_question_attempt_path(q, attempt), params: { attempt: { verdict: "correct" } }

      assert_redirected_to question_path(q)
      assert_equal "correct", attempt.reload.verdict

      sign_in_as(respondent)
      get question_path(q)

      assert_select ".qf-chip.qf-verdict-correct", text: "Правильно"
      assert_select ".qf-stat", text: /Правильно/

      get leaderboard_path

      assert_response :success
      assert_select ".qf-board .qf-row", count: 1
      assert_select ".qf-row .qf-who", text: "Two"
      assert_select ".qf-row .qf-score", text: "1"
    end
  end

  test "attempt at the exact deadline is rejected and enqueues nothing" do
    author = users(:one)
    respondent = users(:two)
    # travel_to drops sub-second precision. A whole-second deadline keeps the clock exactly on it.
    q = author.authored_questions.create!(title: "Граница", body: "Тело",
      answer_type: "text", reference_answer: "Эталон",
      deadline: 1.hour.from_now.change(usec: 0), tags: [])

    travel_to q.deadline do
      sign_in_as(respondent)
      assert_no_difference "Attempt.count" do
        assert_no_enqueued_jobs only: AttemptJuryJob do
          post question_attempts_path(q), params: { attempt: { body: "опоздал ровно" } }
        end
      end

      assert_redirected_to question_path(q)
    end
  end

  test "pending comment becomes visible to a stranger after the deadline" do
    q = questions(:closed_text)
    Comment.create!(question: q, user: q.author, body: "раскрытый pending")
    stranger = User.create!(name: "StrangerReveal", email: "stranger-reveal@example.com",
                            password: "password12345678", password_confirmation: "password12345678")
    sign_in_as(stranger)
    get question_path(q, tab: "comments")

    assert_response :success
    assert_match(/раскрытый pending/, response.body)
  end
end
