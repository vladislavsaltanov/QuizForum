require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "guest is redirected to sign in" do
    get root_path

    assert_redirected_to new_session_path
  end

  test "shows nav, hero, search, filters, cards and sign out" do
    user = users(:one)
    sign_in_as(user)
    get root_path

    assert_response :success
    assert_select ".qf-logo", text: "QuizForum"
    assert_select ".qf-nav-item", text: "Главный экран"
    assert_select ".qf-nav-item", text: "Мои вопросы"
    assert_select ".qf-nav-item", text: "Таблица лидеров"
    assert_select ".qf-nav-item", text: "Профиль"
    assert_select ".qf-kicker", text: /Вопросы · /
    assert_select "h2.qf-section-title", text: /Открытые вопросы · /
    assert_select "h1.qf-hero", text: "Вопросы"
    assert_select "input[name=q]"
    assert_select "select[name=author]"
    assert_select "select[name=difficulty]"
    assert_select "select[name=topic]"
    assert_select ".qf-card", count: 2
    assert_select ".qf-card-num", text: "01"
    assert_select ".qf-card-title", text: /подстроки/
    assert_select ".qf-card-attempts", text: /ответили:/
    assert_select ".qf-chip", text: /до /
    assert_select ".qf-card-link[href=?]", question_path(questions(:open_text))
    assert_select ".qf-footer"
    assert_select ".qf-user-email", text: user.email
    assert_select "form[action=?]", session_path do
      assert_select "button", text: "Выйти"
    end
  end

  test "filters questions by search text and difficulty" do
    user = users(:one)
    sign_in_as(user)
    get root_path, params: { q: "подстроки", difficulty: "среднее" }

    assert_response :success
    assert_select ".qf-card", count: 1
    assert_select ".qf-card-title", text: /подстроки/
  end

  test "filters questions by author" do
    user = users(:one)
    sign_in_as(user)
    get root_path, params: { author: "Two" }

    assert_response :success
    assert_select ".qf-card", count: 1
  end

  test "filters questions by topic" do
    user = users(:one)
    sign_in_as(user)
    get root_path, params: { topic: "алгоритмы" }

    assert_response :success
    assert_select ".qf-card", count: 1
    assert_select ".qf-card-title", text: /подстроки/
  end

  test "hides questions closed longer than the archive grace period" do
    sign_in_as(users(:one))
    ancient = archived_question("Давно закрытый")

    get root_path

    assert_response :success
    assert_select ".qf-card-title", text: /#{Regexp.escape(ancient.title)}/, count: 0
    assert_select ".qf-card-title", text: /подстроки/
  end

  test "kicker and open-group title count exactly the feed questions" do
    sign_in_as(users(:one))
    archived_question("Давно закрытый")

    get root_path

    assert_select ".qf-kicker", text: "Вопросы · #{Question.feed.count}"
    assert_select "h2.qf-section-title", text: "Открытые вопросы · #{Question.feed.count}"
  end

  test "a closing deadline swaps the chip and the archive link counts the archive" do
    sign_in_as(users(:one))
    deadline = 4.hours.from_now
    Question.create!(title: "Скоро закрывается", body: "Тело", answer_type: "text",
                     reference_answer: "Ответ", deadline: deadline,
                     author: users(:one), tags: [ "среднее" ])
    archived_question("Давно закрытый")

    get root_path

    # Countdown digits only: time_left floors, so pinning the exact number would
    # make this test fail whenever the render slips past a whole hour.
    assert_select ".qf-chip-urgent", text: /заканчивается · \d/, count: 1
    assert_select ".qf-chip", text: /до /, minimum: 1
    assert_select "a[href=?]", archive_path, text: "Архив · #{Question.archived.count}"
  end

  test "topic dropdown offers only topics the feed can still return" do
    sign_in_as(users(:one))
    archived_question("Давно закрытый", tags: [ "протоколы" ])

    get root_path

    assert_select "select[name=topic] option[value=?]", "протоколы", count: 0
    assert_select "select[name=topic] option[value=?]", "алгоритмы", count: 1
  end

  test "attempt counters on the cards cost no extra selects" do
    20.times { |i| bulk_question("Массовый #{i}") }
    sign_in_as(users(:one))

    selects = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      selects += 1 if payload[:sql].start_with?("SELECT")
    end
    ActiveRecord::Base.uncached do
      get root_path
      assert_select ".qf-card", count: 20
    end
    ActiveSupport::Notifications.unsubscribe(subscriber)

    assert_operator selects, :<, 20, "cards must not issue one COUNT per question"
  end

  test "splits the index into pages of 20 questions" do
    40.times { |i| bulk_question("Массовый #{i}") }
    sign_in_as(users(:one))

    get root_path
    assert_select ".qf-card", count: 20
    assert_select ".qf-kicker", text: /Вопросы · 42/

    get root_path, params: { page: 2 }
    assert_select ".qf-card", count: 20

    get root_path, params: { page: 3 }
    assert_select ".qf-card", count: 2
  end

  test "pager sits under the cards and keeps the active filters" do
    25.times { |i| bulk_question("Массовый #{i}") }
    sign_in_as(users(:one))
    get root_path, params: { difficulty: "среднее" }

    assert_select ".qf-cards + .qf-pager" do
      assert_select "a[href*='page=2']", minimum: 1
      assert_select "a[href*='difficulty=%D1%81%D1%80%D0%B5%D0%B4%D0%BD%D0%B5%D0%B5']", minimum: 1
    end
  end

  test "pager marks the current page and clamps a page past the last one" do
    25.times { |i| bulk_question("Массовый #{i}") }
    sign_in_as(users(:one))
    get root_path, params: { page: 99 }

    assert_response :success
    assert_select ".qf-card", count: 7
    assert_select ".qf-pager [aria-current=page]", text: "2"
  end

  test "single page of results renders no pager" do
    sign_in_as(users(:one))
    get root_path, params: { q: "подстроки" }

    assert_select ".qf-card", count: 1
    # The archive link below shares the pager's row style, so count the page-turn
    # nav by its own label rather than by class.
    assert_select "nav[aria-label=?]", "Постраничная навигация", count: 0
  end

  test "answered test card shows «решено» mark" do
    stranger = users(:two)
    test = stranger.authored_tests.create!(title: "Решил чужое", deadline: 1.day.from_now, published: true)
    q = test.questions.create!(title: "q", body: "b", answer_type: "text",
      reference_answer: "r", deadline: test.deadline, author: stranger, points: 1, position: 0)
    Attempt.create!(question: q, user: users(:one), body: "мой ответ")

    sign_in_as(users(:one))
    get root_path

    assert_select ".qf-chip", text: "решено", count: 1
  end

  test "own published test stays out of Открытые тесты" do
    user = users(:one)
    user.authored_tests.create!(title: "Сам себе", deadline: 1.day.from_now, published: true)

    sign_in_as(user)
    get root_path

    assert_no_match(/Открытые тесты/, response.body)
    assert_select ".qf-test-mark", count: 0
  end

  test "feed splits into named open and recently-closed groups" do
    sign_in_as(users(:one))
    get root_path

    assert_select "h2.qf-section-title", text: /Открытые вопросы · /
    assert_select "section[aria-label='Открытые вопросы'] .qf-card", minimum: 1
    # Nothing closed in this feed yet: the tail heading must not render.
    assert_select "h2.qf-section-title", text: /Недавно закрытые/, count: 0
  end

  test "recently closed questions appear with their own heading and chip" do
    q = bulk_question("Чуть позже")
    q.update!(deadline: 1.hour.ago)

    sign_in_as(users(:one))
    get root_path

    assert_select "h2.qf-section-title", text: /Недавно закрытые вопросы · 1/
    assert_select "section[aria-label='Недавно закрытые вопросы']" do
      assert_select ".qf-card-title", text: /Чуть позже/
      assert_select ".qf-chip", text: /закрыт/
    end
  end

  private
    def bulk_question(title)
      Question.create!(title: title, body: "Тело", answer_type: "text",
                       reference_answer: "Ответ", deadline: 7.days.from_now,
                       author: users(:one), tags: [ "среднее" ])
    end

    def archived_question(title, tags: [ "среднее" ])
      Question.create!(title: title, body: "Тело", answer_type: "text",
                       reference_answer: "Ответ",
                       deadline: Question::ARCHIVE_GRACE.ago - 1.day,
                       author: users(:one), tags: tags)
    end
end
