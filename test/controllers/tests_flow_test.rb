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

    # No public test index: /tests lists only authored/taken tests. The
    # random test itself stays reachable by direct link (open + published).
    sign_in_as(@user)
    get tests_path
    assert_match(/Мои тесты/, body)
    assert_no_match(/Мидтерм/, body)
    get test_path(test)
    assert_response :success
    assert_match(/Мидтерм/, body)
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

  test "invalid attempt re-renders with typed answers, never others' answers" do
    sign_in_as(@author)
    test = @author.authored_tests.create!(title: "Форма", deadline: 1.day.from_now, published: true)
    q0 = test.questions.create!(title: "А зачем?", body: "b", answer_type: "text",
      reference_answer: "потому", deadline: test.deadline, author: @author, points: 2, position: 0)
    q1 = test.questions.create!(title: "Столица?", body: "b", answer_type: "text",
      reference_answer: "Париж", deadline: test.deadline, author: @author, points: 5, position: 1)
    # Другой пользователь успел ответить; pre-deadline чужие ответы скрыты
    # даже в re-render после ошибки валидации.
    @other.attempts.create!(question: q1, body: "чужой смысл")
    sign_in_as(@user)

    # Один из двух вопросов не заполнен: вся попытка валится, но введённое
    # сохраняется в форме вместо голого redirect, который всё терял.
    post attempt_test_path(test), params: { answers: {
      q0.id.to_s => { body: "" },
      q1.id.to_s => { body: "Париж" }
    } }
    assert_response :unprocessable_entity
    assert_match(/Столица/, response.body)
    assert_select "textarea", text: /Париж/
    assert_no_match(/чужой смысл/, response.body)
    assert_equal 0, Attempt.where(question: q0, user: @user).count
    assert_equal 0, Attempt.where(question: q1, user: @user).count
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

  test "my tests dashboard: sections, drafts first, author chips" do
    sign_in_as(@author)
    @author.authored_tests.create!(title: "Драфт Мид", deadline: 2.days.from_now)
    @author.authored_tests.create!(title: "Открытый Мид", deadline: 3.days.from_now, published: true)
    @author.authored_tests.create!(title: "Заперт Мид", deadline: 3.days.from_now, password: "s3cret", published: true)
    closed = @author.authored_tests.create!(title: "Закрытый Мид", deadline: 1.hour.ago, published: true)
    closed.questions.create!(title: "q", body: "b", answer_type: "text",
      reference_answer: "r", deadline: closed.deadline, author: @author, points: 4, position: 0)

    get tests_path
    assert_response :success
    assert_match(/Мои тесты/, body)
    assert_match(/В работе/, body)
    assert_match(/Завершённые/, body)
    assert_match(/Пройдено мной/, body)
    # Author sees their own password test with its chip.
    assert_match(/Заперт Мид/, body)
    assert_match(/по паролю/, body)
    assert_match(/черновик/, body)
    assert_match(/завершён/, body)
    # Drafts first, then open published, closed into Завершённые.
    assert_operator body.index("Драфт Мид"), :<, body.index("Открытый Мид")
    assert_operator body.index("Открытый Мид"), :<, body.index("Закрытый Мид")
  end

  test "my tests dashboard: taken tests carry score or waiting chip" do
    closed = @author.authored_tests.create!(title: "Сдан Мид", deadline: 1.hour.ago, published: true)
    cq = closed.questions.create!(title: "q", body: "b", answer_type: "single_choice",
      reference_answer: "", deadline: closed.deadline, author: @author, points: 4, position: 0,
      options: [ { "text" => "да", "correct" => true }, { "text" => "нет", "correct" => false } ])
    cq.attempts.create!(user: @user, selected: [ "0" ])
    open = @author.authored_tests.create!(title: "Проходит Мид", deadline: 2.days.from_now, published: true)
    open.questions.create!(title: "q", body: "b", answer_type: "text",
      reference_answer: "r", deadline: open.deadline, author: @author, points: 3, position: 0)
        .tap { |q| q.attempts.create!(user: @user, body: "x") }

    sign_in_as(@user)
    get tests_path
    assert_match(/Сдан Мид/, body)
    assert_match(/балл: 4 из 4/, body)
    assert_match(/Проходит Мид/, body)
    assert_match(/ждёт дедлайна/, body)
    assert_no_match(/балл: 0 из 3/, body)
  end

  test "my tests dashboard: stranger without tests sees empty state" do
    sign_in_as(@other)
    get tests_path
    assert_response :success
    assert_match(/Мои тесты/, body)
    assert_match(/Вы пока не проходили/, body)
    assert_no_match(/qf-card-title/, body)
  end

  test "invalid attempt alert is russian and dashboard cards count respondents" do
    sign_in_as(@author)
    test = @author.authored_tests.create!(title: "Отвечалки", deadline: 1.day.from_now, published: true)
    q0 = test.questions.create!(title: "Выбор", body: "b", answer_type: "single_choice",
      reference_answer: "", deadline: test.deadline, author: @author, points: 1, position: 0,
      options: [ { "text" => "да", "correct" => true }, { "text" => "нет", "correct" => false } ])
    q1 = test.questions.create!(title: "Текст", body: "b", answer_type: "text",
      reference_answer: "а", deadline: test.deadline, author: @author, points: 1, position: 1)

    # Someone answered the choice question: the author's dashboard card says so.
    Attempt.create!(question: q0, user: @other, selected: [ "0" ])
    get tests_path
    assert_select ".qf-chip", text: /ответили: 1/, count: 1

    # The 422 alert speaks Russian and names the failing question.
    sign_in_as(@user)
    post attempt_test_path(test), params: { answers: { q0.id.to_s => { selected: [ "0" ] } } }
    assert_response :unprocessable_entity
    assert_match("Вопрос 2: заполните ответ.", flash.now[:alert].to_s)
    assert_no_match(/Body can't be blank/, flash.now[:alert].to_s)
  end

  test "editor reorders questions and reserves publish for drafts" do
    sign_in_as(@author)
    test = @author.authored_tests.create!(title: "Пересо", deadline: 1.day.from_now)
    q0 = test.questions.create!(title: "Первый", body: "b", answer_type: "text",
      reference_answer: "x", deadline: test.deadline, author: @author, points: 1, position: 0)
    q1 = test.questions.create!(title: "Второй", body: "b", answer_type: "text",
      reference_answer: "y", deadline: test.deadline, author: @author, points: 1, position: 1)

    # The row's ↑ button submits the settings form with questions_move.
    patch test_path(test), params: {
      test: { title: "Пересо", deadline: 1.day.from_now },
      questions_move: { q1.id.to_s => "up" }
    }
    assert_redirected_to edit_test_path(test)
    assert_equal [ q1.id, q0.id ], test.questions.order(:position, :id).pluck(:id)

    # A foreign question id is a no-op: order unchanged, still a redirect.
    patch test_path(test), params: {
      test: { title: "Пересо", deadline: 1.day.from_now },
      questions_move: { "999999" => "up" }
    }
    assert_redirected_to edit_test_path(test)
    assert_equal [ q1.id, q0.id ], test.questions.order(:position, :id).pluck(:id)

    # Publish is a draft-only action; the published edit hides its button.
    get edit_test_path(test)
    assert_select "button[name='publish']", count: 1
    test.update!(published: true)
    get edit_test_path(test)
    assert_select "button[name='publish']", count: 0
  end

  test "wizard markup ships visible steps, no JS-only state in raw HTML" do
    sign_in_as(@author)
    test = @author.authored_tests.create!(title: "Викторина", deadline: 1.day.from_now, published: true)
    test.questions.create!(title: "Раз", body: "b", answer_type: "text", reference_answer: "x",
      deadline: test.deadline, author: @author, points: 1, position: 0)
    test.questions.create!(title: "Два", body: "b", answer_type: "single_choice", reference_answer: "",
      deadline: test.deadline, author: @author, points: 1, position: 1,
      options: [ { "text" => "a", "correct" => true }, { "text" => "b", "correct" => false } ])
    sign_in_as(@user)

    get test_path(test)
    assert_response :success
    # Hooks the wizard script binds to.
    assert_select 'form[data-wizard="1"]'
    assert_select "section.qf-step[data-step]", count: 2
    assert_select "nav.qf-wizard-progress .qf-wizard-dot[data-goto]", count: 2
    assert_select ".qf-wizard-bar .qf-wizard-done"
    assert_select ".qf-wizard-bar button[type='submit']"
    # No-JS fallback: .qf-wizard-on / .qf-step-hint appear only from the inline
    # script or the stylesheet, never as server-rendered class attributes.
    assert_no_match(/class="[^"]*qf-wizard-on/, response.body)
    assert_no_match(/class="[^"]*qf-step-hint/, response.body)
  end
end
