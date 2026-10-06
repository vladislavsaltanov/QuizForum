require "test_helper"

class QuestionDateFilterTest < ActionDispatch::IntegrationTest
  test "home date range stays inside the landing feed" do
    sign_in_as(users(:one))
    from = Date.new(2025, 10, 6)
    to = Date.new(2025, 10, 10)
    feed_question = question("В ленте за период", deadline: 7.days.from_now)
    closed_in_feed = question("Закрытый в ленте", deadline: 1.day.ago)
    archived_question = question("Архивный за период", deadline: Question::ARCHIVE_GRACE.ago - 1.day)
    outside_question = question("Вне периода", deadline: 7.days.from_now)
    feed_question.update_column(:created_at, Time.zone.local(2025, 10, 6))
    closed_in_feed.update_column(:created_at, Time.zone.local(2025, 10, 8))
    archived_question.update_column(:created_at, Time.zone.local(2025, 10, 10, 23, 59, 59, 999_999))
    outside_question.update_column(:created_at, Time.zone.local(2025, 10, 11))

    get root_path, params: { date_from: from.iso8601, date_to: to.iso8601 }

    assert_response :success
    assert_select ".qf-kicker", text: "Вопросы по дате · 2"
    assert_select ".qf-card-meta .qf-chip", text: /закрыт /
    assert_select "button[popovertarget='qf-date-range'].qf-filter", text: "06.10–10.10"
    assert_select "#qf-date-range[popover=auto][role=dialog]" do
      assert_select "input[type=date]", count: 2
    end
    assert_select "input[type=date][name=date_from][value=?]", "2025-10-06"
    assert_select "input[type=date][name=date_to][value=?]", "2025-10-10"
    assert_select ".qf-reset[href=?]", root_path
    assert_select ".qf-card-title", text: "В ленте за период"
    assert_select ".qf-card-title", text: "Закрытый в ленте"
    assert_select ".qf-card-title", text: "Архивный за период", count: 0
    assert_select ".qf-card-title", text: "Вне периода", count: 0
  end

  test "archive date range stays within the selected archive category" do
    sign_in_as(users(:one))
    in_archive = question("Архив внутри диапазона", deadline: Question::ARCHIVE_GRACE.ago - 1.day)
    outside_archive = question("Архив вне диапазона", deadline: Question::ARCHIVE_GRACE.ago - 1.day)
    open_question = question("Открытый вопрос", deadline: 7.days.from_now)
    in_archive.update_column(:created_at, Time.zone.local(2025, 10, 6))
    outside_archive.update_column(:created_at, Time.zone.local(2025, 10, 11))
    open_question.update_column(:created_at, Time.zone.local(2025, 10, 8))

    get archive_path, params: { date_from: "2025-10-06", date_to: "2025-10-10" }

    assert_response :success
    assert_select ".qf-card-title", text: "Архив внутри диапазона"
    assert_select ".qf-card-title", text: "Архив вне диапазона", count: 0
    assert_select ".qf-card-title", text: "Открытый вопрос", count: 0
  end

  test "date range survives pagination" do
    sign_in_as(users(:one))
    21.times do |i|
      question("Страница #{i}", deadline: 7.days.from_now)
        .update_column(:created_at, Time.zone.local(2025, 10, 8) + i.seconds)
    end

    get root_path, params: { date_from: "2025-10-06", date_to: "2025-10-10" }

    assert_select ".qf-card", count: 20
    assert_select ".qf-pager a[href*='date_from=2025-10-06']", minimum: 1
    assert_select ".qf-pager a[href*='date_to=2025-10-10']", minimum: 1
  end

  test "invalid or reversed date range renders a validation message" do
    sign_in_as(users(:one))
    [ { date_from: "not-a-date" }, { date_from: "2025-10-11", date_to: "2025-10-06" } ].each do |range|
      get root_path, params: range

      assert_response :success
      assert_select ".qf-alert[role=alert]", text: "Проверьте диапазон дат."
      assert_select ".qf-card", count: 0
    end
  end

  private
    def question(title, deadline:)
      Question.create!(title:, body: "Условие", answer_type: "text", reference_answer: "Ответ",
                       deadline:, author: users(:one), tags: [])
    end
end
