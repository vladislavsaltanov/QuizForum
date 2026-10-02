require "application_system_test_case"

class CommentScrollTest < ApplicationSystemTestCase
  BOX = "(() => { const c = document.getElementById('comments'); return [c.scrollTop, c.scrollHeight, c.clientHeight]; })()"
  BOTTOM_GAP = "(() => { const c = document.getElementById('comments'); const l = c.lastElementChild; return c.getBoundingClientRect().bottom - l.getBoundingClientRect().bottom; })()"

  # Paging is an async fetch plus a Turbo stream; give both room to land.
  def setup
    Capybara.default_max_wait_time = 5
    super
  end

  test "chat opens on the newest message and keeps its gap from the input" do
    open_chat(25)

    assert_selector "#comments .qf-msg", count: 10
    scroll_top, height, client = box
    assert_equal height - client, scroll_top, "панель должна открыться на последнем сообщении"
    assert_operator bottom_gap, :>=, 8, "под последним сообщением нужен отступ"
  end

  test "scrolling up is not dragged back down by a late re-layout" do
    open_chat(25)
    page.execute_script("document.getElementById('comments').scrollTop = 200")

    sleep 1

    assert_equal 200, box[0]
  end

  test "scrolling to the top prepends ten and pins the reader to the same offset" do
    open_chat(25)
    page.execute_script("document.getElementById('comments').scrollTop = 0")
    before_height = box[1]

    assert_selector "#comments .qf-msg", count: 20

    scroll_top, height, = box
    assert_equal height - before_height, scroll_top, "позиция чтения должна сохраниться"
    assert_no_selector "#comments-more"
  end

  private
    def open_chat(count)
      question = questions(:open_text)
      count.times { |i| question.comments.create!(user: users(:two), body: "Комментарий #{i}", status: "approved") }

      visit new_session_url
      assert_selector "input[name=email]"
      fill_in "email", with: "one@example.com"
      fill_in "password", with: "password-12-plus"
      assert_equal "one@example.com", find("input[name=email]").value
      click_on "Войти"
      assert_no_selector "input[name=email]"
      visit question_url(question, tab: "comments")
      assert_selector "#comments .qf-msg", count: 10
      # Fonts load late; let the follow-up re-layout settle before measuring.
      sleep 1
    end

    def box
      page.evaluate_script(BOX)
    end

    def bottom_gap
      page.evaluate_script(BOTTOM_GAP).to_f
    end
end
