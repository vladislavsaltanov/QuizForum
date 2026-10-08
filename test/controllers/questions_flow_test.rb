require "test_helper"

class QuestionsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:two) # respondent
    @author = users(:one) # author of open_text and closed_single
    sign_in_as(@user)
  end

  test "guest is redirected to sign in" do
    sign_out
    get question_path(questions(:open_text))

    assert_redirected_to new_session_path
  end

  test "open question hides reference and other texts, shows form" do
    Attempt.create!(question: questions(:open_text), user: @author, body: "secret")
    get question_path(questions(:open_text))

    assert_response :success
    assert_select "h1", text: /подстроки/
    assert_select ".qf-tab", text: "Ответы"
    assert_select ".qf-tab", text: "Комментарии"
    assert_select ".qf-count", text: /Всего ответов: 1/
    assert_select "textarea[name='attempt[body]']"
    assert_select "button", text: "Отправить"
    assert_no_match(/secret/, response.body)
    assert_no_match(/префикс-функцию/, response.body)
  end

  test "code form hints the solve entrypoint" do
    sign_in_as(users(:one))
    get question_path(questions(:open_code))

    assert_response :success
    assert_match(/Метод должен называться/, response.body)
    assert_select "textarea[name='attempt[body]']"
  end

  test "text attempt is immutable and pending" do
    q = questions(:open_text)
    post question_attempts_path(q), params: { attempt: { body: "my answer" } }

    assert_redirected_to question_path(q)
    assert_equal "pending", q.attempts.find_by(user: @user).verdict

    post question_attempts_path(q), params: { attempt: { body: "second" } }

    assert_equal 1, q.attempts.where(user: @user).count
    follow_redirect!
    assert_select ".qf-hint", text: /изменить его нельзя/
  end

  test "single choice attempt is graded correct" do
    q = Question.create!(title: "t-graded", body: "b", answer_type: "single_choice",
      options: [ { "text" => "a", "correct" => true }, { "text" => "b", "correct" => false } ],
      reference_answer: "r", deadline: 7.days.from_now, author: @author, tags: [])
    post question_attempts_path(q), params: { attempt: { selected: [ "0" ] } }

    assert_equal "correct", q.attempts.find_by(user: @user).verdict
  end

  test "closed question shows stats, reference, attempts, report button" do
    q = questions(:closed_single)
    Attempt.create!(question: q, user: @author, selected: [ "1" ])
    get question_path(q)

    assert_response :success
    assert_select ".qf-stat", text: /Правильно/
    assert_select ".qf-stat", text: /Почти, но нет/
    assert_select ".qf-stat", text: /Неправильно/
    assert_select ".qf-stat", text: /На проверке/, count: 0
    assert_select "h2", text: "Ответ автора", count: 0
    assert_select "h2", text: "Правильные варианты"
    assert_select "button", text: "Пожаловаться"
    assert_select "button", text: "Поделиться"

    post question_reports_path(q)

    assert_redirected_to question_path(q)
    assert_equal 1, q.reports.where(user: @user).count
  end

  test "summary shows emails to privileged viewers only" do
    q = questions(:closed_single)
    Attempt.create!(question: q, user: @author, selected: [ "1" ])
    get question_path(q)

    assert_response :success
    assert_select ".qf-summary-names"
    assert_no_match(/#{Regexp.escape(@author.email)}/, response.body)

    sign_in_as(@author)
    get question_path(q)

    assert_match(/#{Regexp.escape(@author.email)}/, response.body)
  end

  test "author sees reference and all attempts before deadline" do
    Attempt.create!(question: questions(:open_text), user: @user, body: "visible to author")
    sign_in_as(@author)
    get question_path(questions(:open_text))

    assert_match(/префикс-функцию/, response.body)
    assert_match(/visible to author/, response.body)
  end

  test "comments need approval, strangers do not see pending" do
    q = questions(:open_text)
    with_verdict(:review) do
      post question_comments_path(q, tab: "comments"), params: { comment: { body: "когда дедлайн?" } }
    end

    assert_redirected_to question_path(q, tab: "comments")
    assert_equal "pending", q.comments.find_by(user: @user).status

    stranger = User.create!(name: "Stranger", email: "stranger@example.com",
                            password: "password12345678", password_confirmation: "password12345678")
    sign_in_as(stranger)
    get question_path(q, tab: "comments")

    assert_no_match(/когда дедлайн/, response.body)

    sign_in_as(@author)
    get question_path(q, tab: "comments")

    assert_match(/когда дедлайн/, response.body)
  end

  test "author deletes comment" do
    q = questions(:open_text)
    comment = Comment.create!(question: q, user: @user, body: "удали меня")
    sign_in_as(@author)

    assert_difference("Comment.count", -1) do
      delete question_comment_path(q, comment)
    end

    assert_redirected_to question_path(q, tab: "comments")
  end

  test "stranger cannot delete comment" do
    q = questions(:open_text)
    Comment.create!(question: q, user: @user, body: "не тронь")

    assert_no_difference("Comment.count") do
      delete question_comment_path(q, Comment.last)
    end

    assert_response :forbidden
  end

  test "trustee deletes comment" do
    q = questions(:open_text)
    comment = Comment.create!(question: q, user: @user, body: "лишний")
    trustee = User.create!(name: "TrusteeDel", email: "trusteedel@example.com",
                           password: "password12345678", password_confirmation: "password12345678")
    q.question_trustees.create!(user: trustee)
    sign_in_as(trustee)

    assert_difference("Comment.count", -1) do
      delete question_comment_path(q, comment)
    end
  end

  test "closed question reveals pending comments to strangers" do
    q = questions(:closed_text)
    Comment.create!(question: q, user: q.author, body: "скрытый до проверки")
    stranger = User.create!(name: "StrangerClosed", email: "stranger-closed@example.com",
                            password: "password12345678", password_confirmation: "password12345678")
    sign_in_as(stranger)
    get question_path(q, tab: "comments")

    assert_match(/скрытый до проверки/, response.body)
  end

  test "non-author cannot approve comments" do
    q = questions(:open_text)
    comment = Comment.create!(question: q, user: @user, body: "hi")

    patch approve_question_comment_path(q, comment)

    assert_response :forbidden
    assert_equal "pending", comment.reload.status
  end

  test "open choice questions render radio and checkbox inputs" do
    single = Question.create!(title: "t-single", body: "b", answer_type: "single_choice",
      options: [ { "text" => "a", "correct" => true }, { "text" => "b", "correct" => false } ], reference_answer: "r",
      deadline: 7.days.from_now, author: @author, tags: [])
    get question_path(single)

    assert_select "input[type=radio][name='attempt[selected][]']"

    multiple = Question.create!(title: "t-multi", body: "b", answer_type: "multiple_choice",
      options: [ { "text" => "a", "correct" => true }, { "text" => "b", "correct" => false } ], reference_answer: "r",
      deadline: 7.days.from_now, author: @author, tags: [])
    get question_path(multiple)

    assert_select "input[type=checkbox][name='attempt[selected][]']"
  end

  test "code form offers only runner-gradeable languages" do
    q = Question.create!(title: "t-code", body: "b", answer_type: "code", reference_answer: "r",
      deadline: 7.days.from_now, author: @author, tags: [])
    get question_path(q)

    CodeRunnerClient::SUPPORTED_LANGUAGES.each do |lang|
      assert_select "select[name='attempt[language]'] option", text: lang
    end
    %w[rust sql].each do |lang|
      assert_select "select[name='attempt[language]'] option", text: lang, count: 0
    end
  end

  test "correct choice hides verdict before deadline" do
    q = Question.create!(title: "t-hidden", body: "b", answer_type: "single_choice",
      options: [ { "text" => "a", "correct" => true }, { "text" => "b", "correct" => false } ],
      reference_answer: "r", deadline: 7.days.from_now, author: @author, tags: [])
    post question_attempts_path(q), params: { attempt: { selected: [ "0" ] } }

    assert_equal "correct", q.attempts.find_by(user: @user).verdict
    follow_redirect!
    assert_select ".qf-chip", text: "На проверке"
    assert_no_match(/Правильно/, response.body)
  end

  test "closed verdicts carry color classes" do
    q = questions(:closed_single)
    Attempt.create!(question: q, user: @author, selected: [ "1" ])
    get question_path(q)

    assert_select ".qf-chip.qf-verdict-incorrect", text: "Неправильно"
    assert_select ".qf-stat b.qf-verdict-correct"
  end

  test "attempt notice says moderation" do
    post question_attempts_path(questions(:open_text)), params: { attempt: { body: "x" } }
    follow_redirect!

    assert_select ".qf-notice", text: /Ответ отправлен на модерацию/
  end

  test "comment create shows no flash, only message status" do
    with_verdict(:review) do
      post question_comments_path(questions(:open_text), tab: "comments"), params: { comment: { body: "тихий вопрос" } }
    end
    follow_redirect!

    assert_select ".qf-notice", count: 0
    assert_select ".qf-badge-mute", text: "на модерации"
  end

  test "closed choice shows explanation without reference" do
    q = questions(:closed_single)
    q.update!(explanation: "Потому что range даёт 0, 1, 2.")
    get question_path(q)

    assert_no_match(/\[0, 2, 4\]\./, response.body)
    assert_match(/Потому что range/, response.body)
  end

  test "closed text still shows author reference" do
    get question_path(questions(:closed_text))

    assert_equal 1, assert_select("h2", text: "Ответ автора").size
    assert_match(/Сжимающее отображение/, response.body)
  end

  test "invalid comment redirects with alert" do
    q = questions(:open_text)
    assert_no_difference "Comment.count" do
      post question_comments_path(q, tab: "comments"), params: { comment: { body: "" } }
    end

    assert_redirected_to question_path(q, tab: "comments")
    follow_redirect!
    assert_select ".qf-alert"
  end

  test "author approves comment" do
    q = questions(:open_text)
    comment = Comment.create!(question: q, user: users(:two), body: "please publish")
    sign_in_as(@author)
    patch approve_question_comment_path(q, comment)

    assert_redirected_to question_path(q, tab: "comments")
    assert_equal "approved", comment.reload.status
  end

  test "answers tab subscribes to the question stream and arms the reveal timer" do
    get question_path(questions(:open_text))

    assert_response :success
    assert_select "turbo-frame#question-answers[data-controller='reveal']"
    assert_select "turbo-frame#question-answers[data-reveal-url-value=?]", question_path(questions(:open_text))
  end

  test "verdict on closed question streams chips and stats" do
    q = questions(:closed_single)
    attempt = Attempt.create!(question: q, user: @user, selected: [ "1" ])
    sign_in_as(@author)
    assert_turbo_stream_broadcasts q, count: 4 do
      patch verdict_question_attempt_path(q, attempt), params: { attempt: { verdict: "correct" } }
    end
  end

  test "verdict on open question streams nothing" do
    q = questions(:open_text)
    attempt = Attempt.create!(question: q, user: @user, body: "рано")
    sign_in_as(@author)
    assert_no_turbo_stream_broadcasts q do
      patch verdict_question_attempt_path(q, attempt), params: { attempt: { verdict: "correct" } }
    end
  end

  test "attempt submit escapes the answers frame" do
    get question_path(questions(:open_text))

    assert_select 'form.qf-form[data-turbo-frame="_top"]'
  end

  test "share and composer use stimulus, not inline handlers" do
    get question_path(questions(:open_text))

    assert_select "button[data-controller='share'][data-action='click->share#copy']", minimum: 1
    get question_path(questions(:open_text), tab: "comments")

    assert_select "textarea[data-controller='composer'][data-action='keydown->composer#send']"
    assert_no_match(/onkeydown=/, response.body)
  end

  test "code attempt select is limited to allowed languages" do
    q = @author.authored_questions.create!(title: "Код", body: "Тело",
      answer_type: "code", deadline: 7.days.from_now, reference_answer: "def solve(a):\n  return a",
      code_languages: [ "python", "ruby" ], reference_language: "python")
    get question_path(q)

    assert_response :success
    assert_select "select[name='attempt[language]'] option", 2
    assert_select "select[name='attempt[language]'] option[value='python']", 1
    assert_select "select[name='attempt[language]'] option[value='ruby']", 1
    assert_select "select[name='attempt[language]'] option[value='go']", 0
  end

  test "updating text question with blank languages succeeds" do
    q = questions(:open_text)
    sign_in_as(@author)
    patch question_path(q), params: { question: { title: "Новое", code_languages: [ "" ] } }

    assert_redirected_to question_path(q)
    assert_equal [], q.reload.code_languages
  end

  test "closed summary groups names partial incorrect correct and hides pending" do
    q = questions(:closed_text)
    u3 = User.create!(name: "Three", email: "three@example.com", password: "password12345")
    u4 = User.create!(name: "Four", email: "four@example.com", password: "password12345")
    { users(:one) => [ "correct", "body-one" ], users(:two) => [ "incorrect", "body-two" ],
      u3 => [ "partial", "body-three" ], u4 => [ "pending", "body-four" ] }.each do |user, (verdict, body)|
      attempt = Attempt.create!(question: q, user: user, body: body)
      attempt.update_columns(verdict: verdict)
    end
    sign_in_as(users(:two))
    get question_path(q)

    assert_response :success
    assert_select ".qf-summary-row", 3
    summary_text = css_select(".qf-summary").text
    assert_match(/Частично.*Three.*Неправильно.*Two.*Правильно.*One/m, summary_text)
    assert_match(/three@example\.com/, summary_text)
    assert_no_match(/Four/, summary_text)
    assert_select "details.qf-answers-details:not([open])", 1

    sign_in_as(u4)
    get question_path(q)
    assert_response :success
    assert_select ".qf-summary", 1
  end

  test "open author sees summary but stranger does not" do
    q = questions(:open_text)
    a1 = Attempt.create!(question: q, user: users(:two), body: "b1")
    a1.update_columns(verdict: "correct")
    a2 = Attempt.create!(question: q, user: User.create!(name: "Oth", email: "oth@example.com", password: "password12345"), body: "b2")
    a2.update_columns(verdict: "incorrect")
    sign_in_as(@author)
    get question_path(q)
    assert_select ".qf-summary", 1

    stranger = User.create!(name: "Stranger", email: "stranger@example.com", password: "password12345")
    sign_in_as(stranger)
    get question_path(q)
    assert_select ".qf-summary", 0
  end
  test "stranger pre-deadline sees examples but not reference" do
    q = @author.authored_questions.create!(title: "Код", body: "Тело",
      answer_type: "code", deadline: 7.days.from_now, reference_answer: "def solve(a):\n  return a",
      example_input: "[1]", example_output: "1")
    stranger = User.create!(name: "ExStranger", email: "exstranger@example.com", password: "password12345")
    sign_in_as(stranger)
    get question_path(q)

    assert_response :success
    assert_match(/\[1\]/, response.body)
    assert_no_match(/def solve/, response.body)
  end
end
