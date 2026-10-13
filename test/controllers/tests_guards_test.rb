require "test_helper"

class TestsGuardsTest < ActionDispatch::IntegrationTest
  setup do
    @author = users(:one)
    @stranger = users(:two)
    @test = @author.authored_tests.create!(title: "Мидтерм", deadline: 1.day.from_now, published: true)
    @q0 = @test.questions.create!(title: "Текст?", body: "b", answer_type: "text",
      reference_answer: "да", deadline: @test.deadline, author: @author, points: 3, position: 0)
    @q1 = @test.questions.create!(title: "Выбор?", body: "b", answer_type: "single_choice",
      reference_answer: "", deadline: @test.deadline, author: @author, points: 4, position: 1,
      options: [ { "text" => "4", "correct" => true }, { "text" => "5", "correct" => false } ])
    sign_in_as(@stranger)
  end

  test "stranger cannot edit, update or destroy another author's test" do
    get edit_test_path(@test)
    assert_response :forbidden

    patch test_path(@test), params: { test: { title: "Взлом" } }
    assert_response :forbidden
    assert_equal "Мидтерм", @test.reload.title

    delete test_path(@test)
    assert_response :forbidden
    assert_predicate @test.reload, :published?
  end

  test "question points are saved from the manage screen" do
    sign_in_as(@author)

    patch test_path(@test), params: {
      test: { title: @test.title }, questions_points: { @q0.id.to_s => "7" }
    }

    assert_redirected_to edit_test_path(@test)
    assert_equal 7, @q0.reload.points
  end

  test "author sees their draft without respondents or comments" do
    sign_in_as(@author)
    draft = @author.authored_tests.create!(title: "Черновик", deadline: 1.day.from_now)
    draft.questions.create!(title: "q", body: "b", answer_type: "text", reference_answer: "r",
      deadline: draft.deadline, author: @author, points: 1, position: 0)

    get test_path(draft)

    assert_response :success
    assert_match(/Черновик/, response.body)
    assert_no_match(/Обсуждение/, response.body)
  end

  test "locked test refuses the whole attempt without the password" do
    locked = @author.authored_tests.create!(title: "Заперт", deadline: 1.day.from_now,
      password: "s3cret", published: true)
    locked.questions.create!(title: "q", body: "b", answer_type: "text", reference_answer: "r",
      deadline: locked.deadline, author: @author, points: 1, position: 0)

    post attempt_test_path(locked), params: { answers: {} }

    assert_response :forbidden
    assert_match(/защищён паролем/, response.body)
  end

  test "attempt on a draft bounces with an alert" do
    draft = @author.authored_tests.create!(title: "Дра", deadline: 1.day.from_now)
    draft.questions.create!(title: "q", body: "b", answer_type: "text", reference_answer: "r",
      deadline: draft.deadline, author: @author, points: 1, position: 0)

    post attempt_test_path(draft), params: { answers: {} }

    assert_redirected_to test_path(draft)
    assert_match(/ещё не опубликован/, flash[:alert].to_s)
  end

  test "attempt after the deadline bounces with an alert" do
    @test.update!(deadline: 1.hour.ago)
    @test.questions.update_all(deadline: 1.hour.ago)

    post attempt_test_path(@test), params: { answers: {} }

    assert_redirected_to test_path(@test)
    assert_match(/Дедлайн прошёл/, flash[:alert].to_s)
  end

  test "half-filled or malformed submissions save nothing, keep typed input" do
    # Обе попытки валятся с 422 вместо redirect; введённое остаётся в форме.
    post attempt_test_path(@test), params: { answers: {
      @q0.id.to_s => { body: "частичный ввод" }
    } }
    assert_response :unprocessable_entity
    assert_select "textarea", text: /частичный ввод/
    assert_equal 0, Attempt.where(question: @test.questions).count

    # Мусор среди ответов валяется так же; чистый ряд q1 остаётся отмеченным.
    post attempt_test_path(@test), params: { answers: { @q0.id.to_s => "junk", @q1.id.to_s => { selected: [ "1" ] } } }
    assert_response :unprocessable_entity
    assert_select "input[type='radio'][value='1'][checked]"
    assert_equal 0, Attempt.where(question: @test.questions).count
  end

  test "code answers enqueue the code check" do
    code = @test.questions.create!(title: "Код", body: "b", answer_type: "code",
      reference_answer: "def solve(x): return x", deadline: @test.deadline, author: @author,
      points: 5, position: 2, code_languages: %w[python], reference_language: "python")

    assert_enqueued_with(job: AttemptCodeCheckJob) do
      post attempt_test_path(@test), params: { answers: {
        @q0.id.to_s => { body: "да" },
        @q1.id.to_s => { selected: [ "0" ] },
        code.id.to_s => { body: "print(1)", language: "python" }
      } }
    end

    assert_redirected_to test_path(@test)
  end

  test "dashboard hides others' drafts and password tests, author sees own" do
    @author.authored_tests.create!(title: "Секрет-драфт", deadline: 1.day.from_now)
    @author.authored_tests.create!(title: "Тайник", deadline: 1.day.from_now,
      password: "s3cret", published: true)

    get tests_path
    assert_match(/Мои тесты/, body)
    assert_no_match(/Секрет-драфт/, body)
    assert_no_match(/Тайник/, body)

    sign_in_as(@author)
    get tests_path
    assert_match(/Тайник/, body)
    assert_match(/по паролю/, body)
  end

  test "scoreboard scores a respondent who answered only part of the test" do
    @test.update!(deadline: 1.hour.ago)
    @test.questions.update_all(deadline: 1.hour.ago)
    @q0.attempts.create!(user: @stranger, body: "да", verdict: "correct")

    get test_path(@test)

    assert_response :success
    assert_match(/3 из 7/, response.body)
  end
end
