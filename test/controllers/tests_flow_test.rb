require "test_helper"

class TestsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @author = users(:one)
    @user = users(:two)
    @other = User.create!(name: "Three", email: "three@example.com", password: SecureRandom.hex(16), email_confirmed_at: Time.current)
    sign_in_as(@user)
  end

  test "draft flow: settings, question list, publish at the end" do
    sign_in_as(@author)
    # "Новый тест" opens the creation screen at once: settings, empty
    # title list, add button — no separate settings step.
    get new_test_path
    assert_response :success
    test = Test.order(:created_at).last
    assert_predicate test, :draft?
    assert_match(/Вопросов пока нет/, response.body)
    assert_match(/Новый вопрос/, response.body)
    assert_no_match(/questions_title/, response.body)

    # Title and settings are edited on the same screen.
    patch test_path(test), params: {
      test: { title: "Мидтерм", body: "проверка", deadline: 1.day.from_now }
    }
    assert_redirected_to edit_test_path(test)
    assert_equal "Мидтерм", test.reload.title

    # Draft is invisible to strangers.
    sign_in_as(@user)
    get tests_path
    assert_no_match(/Мидтерм/, response.body)
    get test_path(test)
    assert_redirected_to tests_path

    # Questions go through the bound question screen, one by one.
    sign_in_as(@author)
    post questions_path, params: {
      question: { test_id: test.id, title: "Сколько будет 2+2?", body: "посчитайте",
        answer_type: "single_choice", reference_answer: "",
        options_text: [ "4", "3", "5" ], options_correct: [ "0" ] }
    }
    assert_redirected_to edit_test_path(test)
    post questions_path, params: {
      question: { test_id: test.id, title: "Столица Франции?", body: "назовите",
        answer_type: "text", reference_answer: "Париж" }
    }
    assert_redirected_to edit_test_path(test)
    assert_equal 2, test.questions.count

    # Title list links to each question's edit screen; rows are compact
    # (qf-row, not card) with a points field and a delete button.
    get edit_test_path(test)
    assert_response :success
    assert_match(/Сколько будет 2\+2\?/, response.body)
    q0 = test.questions.order(:position).first
    assert_match(/\/questions\/#{q0.id}\/edit/, response.body)
    assert_select ".qf-row", count: 2
    assert_select ".qf-row .qf-row-drop[data-turbo-method='delete']", count: 2
    assert_select "[aria-label='Баллы за вопрос 1']"

    # A question drops out of the list and bounces back to the manage page.
    # q0 (2+2, 1 point) goes: q1 below carries the 5 points.
    delete question_path(q0)
    assert_redirected_to edit_test_path(test)
    assert_equal 1, test.questions.count
    get edit_test_path(test)
    assert_no_match(/Сколько будет 2\+2\?/, response.body)

    # Empty draft refuses to publish.
    empty = @author.authored_tests.create!(title: "Пустой", deadline: 1.day.from_now)
    patch test_path(empty), params: { test: { title: "Пустой", deadline: 1.day.from_now }, publish: "1" }
    assert_response :unprocessable_entity
    assert_predicate empty.reload, :draft?

    # Publish with points set on the manage page; only q1 (5 points) remains.
    q1 = test.questions.order(:position).last
    patch test_path(test), params: {
      test: { title: "Мидтерм", deadline: 1.day.from_now },
      questions_points: { q1.id.to_s => "5" },
      publish: "1"
    }
    assert_redirected_to test_path(test)
    assert_predicate test.reload, :published?
    assert_equal 5, test.max_score

    # Published test is visible to strangers.
    sign_in_as(@user)
    get tests_path
    assert_match(/Мидтерм/, response.body)
  end

  test "open test flow: answer all at once, post-deadline score" do
    sign_in_as(@author)
    test = @author.authored_tests.create!(title: "Мидтерм", deadline: 1.day.from_now, published: true)
    q0 = test.questions.create!(title: "Сколько будет 2+2?", body: "b", answer_type: "single_choice",
      reference_answer: "", deadline: test.deadline, author: @author, points: 2, position: 0,
      options: [ { "text" => "4", "correct" => true }, { "text" => "3", "correct" => false } ])
    q1 = test.questions.create!(title: "Столица?", body: "b", answer_type: "text",
      reference_answer: "Париж", deadline: test.deadline, author: @author, points: 5, position: 1)
    sign_in_as(@user)

    # Both questions render on one page behind a single submit.
    get test_path(test)
    assert_response :success
    assert_match(/2\+2/, response.body)
    assert_match(/Столица/, response.body)
    assert_match(/Отправить все ответы/, response.body)

    # One submit answers everything: correct choice + text (stays pending).
    post attempt_test_path(test), params: { answers: {
      q0.id.to_s => { selected: [ "0" ] },
      q1.id.to_s => { body: "Париж" }
    } }
    assert_redirected_to test_path(test)
    assert_equal "Попытка записана: все вопросы сразу.", flash[:notice]

    # No answering one question at a time: second submit is rejected as a whole.
    post attempt_test_path(test), params: { answers: { q0.id.to_s => { selected: [ "1" ] } } }
    assert_match(/уже ответили/, flash[:alert].to_s)

    # Pre-deadline: own pending state shown, score hidden.
    get test_path(test)
    assert_response :success
    assert_match(/На проверке/, response.body)
    assert_no_match(/из 7/, response.body)

    # Post-deadline: "X из Y" with NULL max_points = sum (2+5=7), partial-half rule.
    Attempt.where(question: q0, user: @user).update_all(verdict: "partial")
    test.update!(deadline: 1.hour.ago)
    get test_path(test)
    assert_response :success
    # partial on 2 points => 1; pending text => 0; total "1 из 7".
    assert_match(/1 из 7/, response.body)
  end

  test "test questions live only inside the test" do
    sign_in_as(@author)
    test = @author.authored_tests.create!(title: "Вложенный", deadline: 1.day.from_now, published: true)
    question = test.questions.create!(title: "Сколько?", body: "b", answer_type: "text",
      reference_answer: "много", deadline: test.deadline, author: @author, points: 1, position: 0)

    # Never on the feed or archive.
    get root_path
    assert_no_match(/Сколько\?/, response.body)
    get archive_path
    assert_no_match(/Сколько\?/, response.body)

    # Standalone question page bounces to the test.
    get question_path(question)
    assert_redirected_to test_path(test)

    # Standalone attempt creation bounces to the test, creates nothing.
    sign_in_as(@user)
    post question_attempts_path(question), params: { attempt: { body: "x" } }
    assert_redirected_to test_path(test)
    assert_equal 0, Attempt.where(question: question).count
  end

  test "password gate denies without password, allows with it" do
    test = @author.authored_tests.create!(title: "Закрытый", deadline: 1.day.from_now, password: "s3cret", published: true)
    test.questions.create!(title: "Вопрос", body: "b", answer_type: "text",
      reference_answer: "да", deadline: test.deadline, author: @author, points: 1, position: 0)

    get test_path(test)
    assert_response :success
    assert_match(/защищён паролем/, response.body)
    assert_no_match(/Вопрос/, response.body)

    post authenticate_test_path(test), params: { password: "wrong" }
    assert_redirected_to test_path(test)
    assert_equal "Неверный пароль.", flash[:alert]

    post authenticate_test_path(test), params: { password: "s3cret" }
    assert_redirected_to test_path(test)
    get test_path(test)
    assert_match(/Вопрос/, response.body)
  end

  test "others' totals hidden before deadline, visible after" do
    test = @author.authored_tests.create!(title: "Приват", deadline: 1.day.from_now, published: true)
    question = test.questions.create!(title: "2+2?", body: "b", answer_type: "single_choice",
      deadline: test.deadline, author: @author, points: 4, position: 0,
      options: [ { "text" => "4", "correct" => true }, { "text" => "5", "correct" => false } ])
    question.attempts.create!(user: @other, selected: [ "0" ]) # correct => 4
    question.attempts.create!(user: @user, selected: [ "1" ]) # incorrect => 0

    get test_path(test)
    assert_response :success
    assert_no_match(/Результаты/, response.body)

    test.update!(deadline: 1.hour.ago)
    get test_path(test)
    assert_response :success
    assert_match(/Результаты/, response.body)
    assert_match(/4 из 4/, response.body)
    assert_match(/0 из 4/, response.body)
  end

  test "partial on odd points rounds half down" do
    test = @author.authored_tests.create!(title: "Округление", deadline: 1.hour.ago, published: true)
    question = test.questions.create!(title: "t", body: "b", answer_type: "text",
      reference_answer: "r", deadline: test.deadline, author: @author, points: 5, position: 0)
    question.attempts.create!(user: @user, body: "x", verdict: "partial")
    assert_equal 2, test.total_score(@user)
    assert_equal 5, test.max_score
  end

  test "explicit max_points overrides question sum" do
    test = @author.authored_tests.create!(title: "Овер", deadline: 1.day.from_now, max_points: 10, published: true)
    test.questions.create!(title: "a", body: "b", answer_type: "text",
      reference_answer: "r", deadline: test.deadline, author: @author, points: 1, position: 0)
    test.questions.create!(title: "b", body: "b", answer_type: "text",
      reference_answer: "r", deadline: test.deadline, author: @author, points: 2, position: 1)
    assert_equal 10, test.max_score
  end

  test "test questions do not leak into the leaderboard" do
    test = @author.authored_tests.create!(title: "Без рейтинга", deadline: 1.hour.ago, published: true)
    question = test.questions.create!(title: "q", body: "b", answer_type: "single_choice",
      deadline: test.deadline, author: @author, points: 3, position: 0,
      options: [ { "text" => "да", "correct" => true }, { "text" => "нет", "correct" => false } ])
    question.attempts.create!(user: @user, selected: [ "0" ]) # correct, revealed
    assert_empty Attempt.revealed_points.select { |u, _| u == @user }
  end

  test "draft can be dropped, published test cannot" do
    sign_in_as(@author)
    get new_test_path
    draft = Test.order(:created_at).last
    delete test_path(draft)
    assert_redirected_to tests_path
    assert_nil Test.find_by(id: draft.id)

    published = @author.authored_tests.create!(title: "Живой", deadline: 1.day.from_now, published: true)
    delete test_path(published)
    assert_redirected_to tests_path
    assert_predicate published.reload, :published?
  end

  test "author cannot answer their own test, sees author plate and no form" do
    sign_in_as(@author)
    test = @author.authored_tests.create!(title: "Свой", deadline: 1.day.from_now, published: true)
    question = test.questions.create!(title: "q", body: "b", answer_type: "text",
      reference_answer: "r", deadline: test.deadline, author: @author, points: 2, position: 0)

    get test_path(test)
    assert_response :success
    assert_match(/Это ваш тест/, response.body)
    assert_select "form[action='#{attempt_test_path(test)}']", count: 0
    assert_select ".qf-author-card", text: /#{@author.name}/

    post attempt_test_path(test), params: { answers: { question.id.to_s => { body: "списал" } } }
    assert_redirected_to test_path(test)
    assert_match(/Автор не отвечает/, flash[:alert].to_s)
    assert_equal 0, Attempt.where(question: question).count
  end

  test "test comments: live pass, Laya pending until author approves" do
    test = @author.authored_tests.create!(title: "Чат", deadline: 1.day.from_now, published: true)
    sign_in_as(@user)

    # Laya pass publishes right away.
    post test_comments_path(test), params: { comment: { body: "Норм тест" } }
    assert_redirected_to test_path(test)
    comment = test.comments.first
    assert_predicate comment, :approved?

    # Flagged comment waits pending; strangers see only their own.
    with_verdict(:flag, "ABUSE") do
      post test_comments_path(test), params: { comment: { body: "Замеченное" } }
    end
    pending = test.comments.find_by(status: "pending")
    assert_equal "pending", pending.status

    sign_in_as(@other)
    get test_path(test)
    assert_match(/Норм тест/, response.body)
    assert_no_match(/Замеченное/, response.body)

    # Only the author publishes it; then it is visible to everyone.
    patch approve_test_comment_path(test, pending)
    assert_response :forbidden
    sign_in_as(@author)
    patch approve_test_comment_path(test, pending)
    assert_redirected_to test_path(test)
    assert_equal "approved", pending.reload.status
  end
end
