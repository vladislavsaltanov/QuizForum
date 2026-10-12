require "test_helper"

class TestsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @author = users(:one)
    @user = users(:two)
    @other = User.create!(name: "Three", email: "three@example.com", password: SecureRandom.hex(16), email_confirmed_at: Time.current)
    sign_in_as(@user)
  end

  test "creation configures all questions inline and publishes at once" do
    sign_in_as(@author)
    # Builder page: question list with per-question points plus the add button.
    get new_test_path
    assert_response :success
    assert_match(/Добавить вопрос/, response.body)
    assert_match(/questions_points/, response.body)

    post tests_path, params: {
      test: { title: "Мидтерм", body: "проверка", deadline: 1.day.from_now, max_points: "" },
      questions_title: [ "Сколько будет 2+2?", "Столица Франции?" ],
      questions_answer_type: %w[single_choice text],
      questions_body: [ "посчитайте", "назовите" ],
      questions_reference: [ "", "Париж" ],
      questions_points: %w[2 5],
      questions_options: [ "*4\n3\n5", "" ]
    }
    test = Test.order(:created_at).last
    assert_redirected_to test_path(test)
    assert_equal 2, test.questions.count
    assert_equal 7, test.max_score
    # Question deadlines follow the test.
    assert_equal [ test.deadline ], test.questions.map(&:deadline).uniq

    # Manage page lists titles linking to each question's edit screen.
    get edit_test_path(test)
    assert_response :success
    assert_match(/Сколько будет 2\+2\?/, response.body)
    assert_match(/Столица Франции\?/, response.body)
    q0 = test.questions.order(:position).first
    assert_match(/\/questions\/#{q0.id}\/edit/, response.body)
    assert_match(/Новый вопрос/, response.body)

    # Points are set on the manage page.
    q1 = test.questions.order(:position).last
    patch test_path(test), params: {
      test: { title: "Мидтерм", deadline: 1.day.from_now },
      questions_points: { q0.id.to_s => "3", q1.id.to_s => "5" }
    }
    assert_redirected_to edit_test_path(test)
    assert_equal 3, q0.reload.points
    assert_equal 8, test.reload.max_score
  end

  test "post-publish questions are added through the bound question screen" do
    sign_in_as(@author)
    post tests_path, params: {
      test: { title: "Дополняемый", deadline: 1.day.from_now },
      questions_title: [ "Первый?" ],
      questions_answer_type: [ "text" ],
      questions_body: [ "b" ],
      questions_reference: [ "да" ],
      questions_points: [ "1" ],
      questions_options: [ "" ]
    }
    test = Test.order(:created_at).last
    post questions_path, params: {
      question: { test_id: test.id, title: "Второй?", body: "b",
        answer_type: "text", reference_answer: "нет" }
    }
    assert_redirected_to edit_test_path(test)
    assert_equal 2, test.questions.count
  end

  test "open test flow: answer all at once, post-deadline score" do
    sign_in_as(@author)
    post tests_path, params: {
      test: { title: "Мидтерм", deadline: 1.day.from_now },
      questions_title: [ "Сколько будет 2+2?", "Столица?" ],
      questions_answer_type: %w[single_choice text],
      questions_body: [ "b", "b" ],
      questions_reference: [ "", "Париж" ],
      questions_points: %w[2 5],
      questions_options: [ "*4\n3", "" ]
    }
    test = Test.order(:created_at).last
    q0, q1 = test.questions.order(:position).to_a
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
    post tests_path, params: {
      test: { title: "Вложенный", deadline: 1.day.from_now },
      questions_title: [ "Сколько?" ],
      questions_answer_type: [ "text" ],
      questions_body: [ "b" ],
      questions_reference: [ "много" ],
      questions_points: [ "1" ],
      questions_options: [ "" ]
    }
    test = Test.order(:created_at).last
    question = test.questions.first

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
    test = @author.authored_tests.create!(title: "Закрытый", deadline: 1.day.from_now, password: "s3cret")
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
    test = @author.authored_tests.create!(title: "Приват", deadline: 1.day.from_now)
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
    test = @author.authored_tests.create!(title: "Округление", deadline: 1.hour.ago)
    question = test.questions.create!(title: "t", body: "b", answer_type: "text",
      reference_answer: "r", deadline: test.deadline, author: @author, points: 5, position: 0)
    question.attempts.create!(user: @user, body: "x", verdict: "partial")
    assert_equal 2, test.total_score(@user)
    assert_equal 5, test.max_score
  end

  test "explicit max_points overrides question sum" do
    test = @author.authored_tests.create!(title: "Овер", deadline: 1.day.from_now, max_points: 10)
    test.questions.create!(title: "a", body: "b", answer_type: "text",
      reference_answer: "r", deadline: test.deadline, author: @author, points: 1, position: 0)
    test.questions.create!(title: "b", body: "b", answer_type: "text",
      reference_answer: "r", deadline: test.deadline, author: @author, points: 2, position: 1)
    assert_equal 10, test.max_score
  end

  test "test questions do not leak into the leaderboard" do
    test = @author.authored_tests.create!(title: "Без рейтинга", deadline: 1.hour.ago)
    question = test.questions.create!(title: "q", body: "b", answer_type: "single_choice",
      deadline: test.deadline, author: @author, points: 3, position: 0,
      options: [ { "text" => "да", "correct" => true }, { "text" => "нет", "correct" => false } ])
    question.attempts.create!(user: @user, selected: [ "0" ]) # correct, revealed
    assert_empty Attempt.revealed_points.select { |u, _| u == @user }
  end
end
