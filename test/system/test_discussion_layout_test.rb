require "application_system_test_case"

# The test discussion column is capped to the question-pane width; nothing
# in it may overflow horizontally, and the composer must sit right under
# the chat instead of being stretched past the fold.
class TestDiscussionLayoutTest < ApplicationSystemTestCase
  # Turbo broadcasts comment appends through ActionBroadcastJob; the test
  # queue adapter swallows them, so the live bubble never reaches the page.
  setup { Turbo::Streams::ActionBroadcastJob.queue_adapter = :inline }

  PROBE_WINDOW = "document.documentElement.scrollWidth - window.innerWidth"
  PROBE_CLIPPED = "(() => { const c = document.getElementById('comments'); return c.scrollWidth - c.clientWidth; })()"
  PROBE_BUBBLE = "(() => { const b = document.querySelector('.qf-msg .qf-bubble'); const c = document.querySelector('.qf-test-discuss'); return b.getBoundingClientRect().right - c.getBoundingClientRect().right; })()"
  PROBE_GAP = "(() => { const c = document.getElementById('comments').getBoundingClientRect(); const b = document.querySelector('.qf-chatbar').getBoundingClientRect(); return b.top - c.bottom; })()"
  PROBE_TALL = "(() => { const r = document.querySelector('.qf-test-discuss').getBoundingClientRect(); return r.bottom - r.top; })()"

  test "no horizontal overflow in the discussion row" do
    open_discussion
    assert_equal 0, page.evaluate_script(PROBE_WINDOW)
    assert_equal 0, page.evaluate_script(PROBE_CLIPPED)
    past = page.evaluate_script(PROBE_BUBBLE)
    assert_operator past, :<=, 0, "bubble must stay inside the discussion column, was #{past}px past"
  end

  test "author deletes a comment from the test page" do
    open_discussion
    initial = page.all("#comments .qf-msg").size
    within(all("#comments .qf-msg").last) { click_on "Удалить" }

    assert_no_text(@test_t.comments.first.body) # removal lands on the page
    assert_equal initial - 1, @test_t.comments.count
  end

  test "sending keeps the composer pinned and updates the live count" do
    open_discussion
    top = page.evaluate_script("(() => { const b = document.querySelector('.qf-chatbar').getBoundingClientRect(); return b.top; })()")
    count_before = page.evaluate_script("document.getElementById('test-comments-count').textContent")

    page.find(".qf-chat-input").set("стабильный композер под постоянным чатом")
    page.find(".qf-send").click()
    assert_text "стабильный композер под постоянным чатом"
    top_after = page.evaluate_script("(() => { const b = document.querySelector('.qf-chatbar').getBoundingClientRect(); return b.top; })()")
    assert_equal top, top_after, "composer must not move when a bubble lands"
    assert_equal (count_before.to_i + 1).to_s, page.evaluate_script("document.getElementById('test-comments-count').textContent")
  end

  test "composer sits right under the chat, inside one fold" do
    open_discussion
    gap = page.evaluate_script(PROBE_GAP)
    assert_operator gap, :>=, 8, "composer detached from chat by #{gap}px"
    height = page.evaluate_script(PROBE_TALL)
    assert_operator height, :<=, 900, "discussion column taller than a fold, was #{height.round}px"
  end

  test "sending a comment does not navigate the page" do
    open_discussion
    page.find(".qf-chat-input").set("новое сообщение которое не должно дёргать страницу")
    page.find(".qf-send").click()

    assert_text "новое сообщение которое не должно дёргать страницу"
    assert_current_path test_path(@test_t) # Turbo stream response: no Drive visit, URL never changes
    assert_selector "#comments .qf-msg", count: 2
  end

  private
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
