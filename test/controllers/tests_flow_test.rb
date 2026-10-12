require "test_helper"

class TestsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @author = users(:one)
    @user = users(:two)
    @other = User.create!(name: "Three", email: "three@example.com", password: SecureRandom.hex(16), email_confirmed_at: Time.current)
    sign_in_as(@user)
  end

  test "open test flow: create, switch tasks, attempt, post-deadline score" do
    sign_in_as(@author)
    post tests_path, params: {
      test: { title: "Мидтерм", body: "проверка", deadline: 1.day.from_now, max_points: "" },
      tasks_body: [ "Сколько будет 2+2?", "Столица Франции?" ],
      tasks_answer_type: %w[single_choice text],
      tasks_points: %w[2 5],
      tasks_options: [ "*4\n3\n5", "" ]
    }
    test = Test.order(:created_at).last
    assert_redirected_to test_path(test)
    sign_in_as(@user)

    # Task switching without reload breaking: both tabs render their task.
    get test_path(test, task: 0)
    assert_response :success
    assert_match(/2\+2/, response.body)
    get test_path(test, task: 1)
    assert_response :success
    assert_match(/Столица/, response.body)

    # Attempt task 0 (correct choice) and task 1 (text, stays pending).
    post attempt_test_path(test, task: 0), params: { test_attempt: { selected: [ "0" ] } }
    assert_redirected_to test_path(test, task: 0)
    post attempt_test_path(test, task: 1), params: { test_attempt: { body: "Париж" } }
    assert_redirected_to test_path(test, task: 1)

    # One attempt per task enforced.
    post attempt_test_path(test, task: 0), params: { test_attempt: { selected: [ "1" ] } }
    assert_match(/уже|taken/i, flash[:alert].to_s)

    # Pre-deadline: no verdicts or texts shown for own pending, score hidden.
    get test_path(test, task: 1)
    assert_response :success
    assert_match(/На проверке/, response.body)
    assert_no_match(/из 7/, response.body)

    # Post-deadline: "X из Y" with NULL max_points = sum (2+5=7), partial-half rule.
    task0 = test.test_tasks.order(:position).first
    TestAttempt.where(test_task: task0, user: @user).update_all(verdict: "partial")
    test.update!(deadline: 1.hour.ago)
    get test_path(test, task: 0)
    assert_response :success
    # partial on 2 points => 1; pending text => 0; total "1 из 7".
    assert_match(/1 из 7/, response.body)
  end

  test "password gate denies without password, allows with it" do
    test = @author.authored_tests.create!(title: "Закрытый", deadline: 1.day.from_now, password: "s3cret")
    test.test_tasks.create!(body: "Задание", position: 0)

    get test_path(test)
    assert_response :success
    assert_match(/защищён паролем/, response.body)
    assert_no_match(/Задание/, response.body)

    post authenticate_test_path(test), params: { password: "wrong" }
    assert_redirected_to test_path(test)
    assert_equal "Неверный пароль.", flash[:alert]

    post authenticate_test_path(test), params: { password: "s3cret" }
    assert_redirected_to test_path(test)
    get test_path(test)
    assert_match(/Задание/, response.body)
  end

  test "others' attempts hidden before deadline, totals visible after" do
    test = @author.authored_tests.create!(title: "Приват", deadline: 1.day.from_now)
    task = test.test_tasks.create!(body: "2+2?", answer_type: "single_choice", position: 0,
      points: 4, options: [ { "text" => "4", "correct" => true }, { "text" => "5", "correct" => false } ])
    task.test_attempts.create!(user: @other, selected: [ "0" ]) # correct => 4
    task.test_attempts.create!(user: @user, selected: [ "1" ]) # incorrect => 0

    get test_path(test, task: 0)
    assert_response :success
    assert_no_match(/Результаты/, response.body)

    test.update!(deadline: 1.hour.ago)
    get test_path(test, task: 0)
    assert_response :success
    assert_match(/Результаты/, response.body)
    assert_match(/4 из 4/, response.body)
    assert_match(/0 из 4/, response.body)
  end

  test "partial on odd points rounds half down" do
    test = @author.authored_tests.create!(title: "Округление", deadline: 1.hour.ago)
    task = test.test_tasks.create!(body: "t", position: 0, points: 5)
    task.test_attempts.create!(user: @user, body: "x", verdict: "partial")
    assert_equal 2, test.total_score(@user)
    assert_equal 5, test.max_score
  end

  test "explicit max_points overrides task sum" do
    test = @author.authored_tests.create!(title: "Овер", deadline: 1.day.from_now, max_points: 10)
    test.test_tasks.create!(body: "a", position: 0, points: 1)
    test.test_tasks.create!(body: "b", position: 1, points: 2)
    assert_equal 10, test.max_score
  end
end
