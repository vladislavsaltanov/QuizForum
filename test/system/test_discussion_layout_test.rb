require "application_system_test_case"

# The test discussion mirrors the question comment pane: blurred sticky head,
# capped 70vh column, pinned composer once saturated. Nothing in the
# discussion row may overflow horizontally, and a send must not move the page.
class TestDiscussionLayoutTest < ApplicationSystemTestCase
  # Turbo broadcasts comment appends through ActionBroadcastJob; the test
  # queue adapter swallows them, so the live bubble never reaches the page.
  setup { Turbo::Streams::ActionBroadcastJob.queue_adapter = :inline }

  DOC_TOP = "(() => { const b = document.querySelector('.qf-chatbar'); return b.getBoundingClientRect().top + window.scrollY; })()"
  PANE_TOP = "(() => document.querySelector('.qf-test-discuss').getBoundingClientRect().top + window.scrollY)()"
  PANE_HEIGHT = "(() => document.querySelector('.qf-test-discuss').getBoundingClientRect().height)()"

  test "no horizontal overflow in the discussion row" do
    open_discussion
    assert_equal 0, page.evaluate_script("document.documentElement.scrollWidth - window.innerWidth")
    assert_equal 0, page.evaluate_script("(() => { const c = document.getElementById('comments'); return c.scrollWidth - c.clientWidth; })()")
    past = page.evaluate_script("(() => { const b = document.querySelector('.qf-msg .qf-bubble'); const c = document.querySelector('.qf-test-discuss'); return b.getBoundingClientRect().right - c.getBoundingClientRect().right; })()")
    assert_operator past, :<=, 0, "bubble must stay inside the discussion column, was #{past}px past"
  end

  test "author deletes a comment from the test page" do
    open_discussion
    initial = page.all("#comments .qf-msg").size
    # Capture before the click: on CI the DELETE can already have destroyed the
    # record by the time this assert evaluates, leaving comments.last as nil.
    message = @test_t.comments.last.body
    within(all("#comments .qf-msg").last) { click_on "Удалить" }

    assert_no_text(message)
    assert_equal initial - 1, @test_t.comments.count
  end

  test "discuss pane is capped and the composer pin holds across sends" do
    open_discussion
    # The column grows to its 70vh cap, then stays put: saturate it so the
    # stability claim bites.
    14.times { |i| @test_t.comments.create!(user: users(:two), body: "насыщалка #{i}", status: "approved") }
    visit page.current_url
    assert_selector "#comments .qf-msg", count: 15
    sleep 1                       # Turbo render + fonts settle before measuring
    sleep 0.5

    top = docs_top
    assert_operator page.evaluate_script(PANE_HEIGHT), :<=, 1000, "pane cap exceeded"

    count_before = page.evaluate_script("document.getElementById('test-comments-count').textContent")
    page.find(".qf-chat-input").set("стабильный композер под постоянным чатом")
    page.find(".qf-send").click()
    assert_text "стабильный композер под постоянным чатом"
    # Own fresh bubble rides the manage stream: it carries the delete button.
    within(all("#comments .qf-msg").last) { assert_selector "button", text: "Удалить" }

    assert_equal top, docs_top, "composer must not move when a bubble lands (#{top.inspect} -> #{docs_top.inspect})"
    assert_equal (count_before.to_i + 1).to_s, page.evaluate_script("document.getElementById('test-comments-count').textContent")
  end

  test "sending a comment does not navigate the page" do
    open_discussion
    page.find(".qf-chat-input").set("новое сообщение которое не должно дёргать страницу")
    page.find(".qf-send").click()

    assert_text "новое сообщение которое не должно дёргать страницу"
    assert_current_path test_path(@test_t) # Turbo stream response: no Drive visit
    assert_selector "#comments .qf-msg", count: 2
  end

  test "composer sits right under the chat, inside one fold" do
    open_discussion
    gap = page.evaluate_script("(() => { const c = document.getElementById('comments').getBoundingClientRect(); const b = document.querySelector('.qf-chatbar').getBoundingClientRect(); return b.top - c.bottom; })()")
    assert_operator gap, :>=, -120, "composer detached from chat by #{gap}px"
    height = page.evaluate_script("(() => { const r = document.querySelector('.qf-test-discuss').getBoundingClientRect(); return r.bottom - r.top; })()")
    assert_operator height, :<=, 900, "discussion column taller than a fold, was #{height.round}px"
  end

  private
    def docs_top
      page.evaluate_script(DOC_TOP)
    end

    def open_discussion
      @author = users(:one)
      @test_t = @author.authored_tests.create!(title: "Клей", body: "b", deadline: 1.day.from_now, published: true)
      question = @test_t.questions.create!(title: "q", body: "b", answer_type: "text",
        reference_answer: "r", deadline: @test_t.deadline, author: @author, points: 1, position: 0)
      question.attempts.create!(user: users(:two), body: "моя попытка")
      @test_t.comments.create!(user: users(:two), body: "первое сообщение для промера рядком", status: "approved")

      visit new_session_url
      fill_in "email", with: "one@example.com"
      fill_in "password", with: "password-12-plus"
      click_on "Войти"
      sleep 0.5                     # Turbo Drive settles the redirect
      visit test_url(@test_t)
      assert_selector "#comments .qf-msg"
    end
end
