require "test_helper"

class ArchiveControllerTest < ActionDispatch::IntegrationTest
  test "guest is redirected to sign in" do
    get archive_path

    assert_redirected_to new_session_path
  end

  test "lists only questions closed past the archive grace period" do
    sign_in_as(users(:one))
    archived = archived_question("Ушёл в архив")

    get archive_path

    assert_response :success
    assert_select "h1.qf-hero", text: "Архив"
    assert_select ".qf-kicker", text: /Архив · /
    assert_select ".qf-card-title", text: /#{Regexp.escape(archived.title)}/
    assert_select ".qf-card-title", text: /подстроки/, count: 0
    assert_select ".qf-back[href=?]", root_path, text: "← К открытым вопросам"
  end

  test "keeps the weekly tail out of the archive" do
    sign_in_as(users(:one))
    tail = Question.create!(title: "Ещё в ленте", body: "Тело", answer_type: "text",
                            reference_answer: "Ответ", deadline: 1.day.ago,
                            author: users(:one), tags: [ "среднее" ])

    get archive_path

    assert_select ".qf-card-title", text: /#{Regexp.escape(tail.title)}/, count: 0
  end

  test "splits the archive into pages of 20 questions" do
    22.times { |i| archived_question("Архивный #{i}") }
    sign_in_as(users(:one))

    get archive_path
    assert_select ".qf-card", count: 20
    assert_select ".qf-pager-count", text: "Стр. 1 из 2"

    get archive_path, params: { page: 2 }
    assert_select ".qf-card", count: 5
  end

  test "card shows the closing date and links to the question" do
    sign_in_as(users(:one))
    archived = archived_question("Ушёл в архив")

    get archive_path

    assert_select ".qf-card-link[href=?]", question_path(archived) do
      assert_select ".qf-chip", text: /закрыт /
      assert_select ".qf-card-num", text: "01"
    end
  end

  test "empty archive says so" do
    Question.where(deadline: ..Question::ARCHIVE_GRACE.ago).delete_all
    sign_in_as(users(:one))

    get archive_path

    assert_select ".qf-empty", text: /В архиве пока пусто/
  end

  test "filters the archive by text and topic" do
    # Tags the fixtures do not use, so a filter can only match what this test made.
    sign_in_as(users(:one))
    wanted = archived_question("Протокол разбора", tags: [ "архивный" ])
    other = archived_question("Совсем другое", tags: [ "разное" ])

    get archive_path, params: { q: "разбора" }
    assert_select ".qf-card", count: 1
    assert_select ".qf-card-title", text: /#{Regexp.escape(wanted.title)}/

    get archive_path, params: { topic: "архивный" }
    assert_select ".qf-card", count: 1
    assert_select ".qf-card-title", text: /#{Regexp.escape(wanted.title)}/

    # The other topic leads to the other question, so the filter really discriminates.
    get archive_path, params: { topic: "разное" }
    assert_select ".qf-card", count: 1
    assert_select ".qf-card-title", text: /#{Regexp.escape(other.title)}/

    get archive_path, params: { q: "разбора" }
    assert_select ".qf-reset[href=?]", archive_path
  end

  test "archive filters can never reach the open feed" do
    sign_in_as(users(:one))
    open_question = Question.create!(title: "Открытый вопрос", body: "Тело", answer_type: "text",
                                     reference_answer: "Ответ", deadline: 7.days.from_now,
                                     author: users(:one), tags: [ "программирование" ])

    get archive_path, params: { q: "Открытый" }

    assert_select ".qf-card", count: 0
    assert_select ".qf-empty", text: /Ничего не найдено/
    assert_select ".qf-card-title", text: /#{Regexp.escape(open_question.title)}/, count: 0
    assert_select ".qf-reset[href=?]", archive_path
  end

  test "topic dropdown offers only topics the archive can return" do
    sign_in_as(users(:one))
    archived_question("Только тут", tags: [ "архивный" ])
    live_tag = "живаятема"
    Question.create!(title: "Живой вопрос", body: "Тело", answer_type: "text",
                     reference_answer: "Ответ", deadline: 7.days.from_now,
                     author: users(:one), tags: [ live_tag ])

    get archive_path

    assert_select "select[name=topic] option[value=?]", live_tag, count: 0
    assert_select "select[name=topic] option[value=?]", "архивный", count: 1
    assert_select ".qf-card-title", text: /Живой вопрос/, count: 0
  end

  private
    def archived_question(title, tags: [ "среднее" ])
      Question.create!(title: title, body: "Тело", answer_type: "text",
                       reference_answer: "Ответ",
                       deadline: Question::ARCHIVE_GRACE.ago - 1.day,
                       author: users(:one), tags: tags)
    end
end
