require "application_system_test_case"

class CommentScrollTest < ApplicationSystemTestCase
  BOX = "(() => { const c = document.getElementById('comments'); return [c.scrollTop, c.scrollHeight, c.clientHeight]; })()"
  THREAD_GAP = "(() => { const c = document.getElementById('comments'); const l = c.lastElementChild; return c.getBoundingClientRect().bottom - l.getBoundingClientRect().bottom; })()"
  COMPOSER = "(() => { const r = document.querySelector('.qf-chatbar').getBoundingClientRect(); return [r.top, r.bottom, window.innerHeight - r.bottom]; })()"

  # Paging is an async fetch plus a Turbo stream; give both room to land.
  def setup
    Capybara.default_max_wait_time = 5
    super
  end

  test "chat opens on the newest message, fully on screen with air around it" do
    open_chat(25)

    assert_selector "#comments .qf-msg", count: 10
    scroll_top, height, client = box
    assert_equal height - client, scroll_top, "лента должна открыться на последнем сообщении"
    assert_operator thread_gap, :>=, 16, "под последним сообщением нужен отступ"

    top, bottom, air = composer
    assert_operator top, :>=, 0, "поле ввода не должно уезжать под верхний край"
    assert_operator bottom, :<=, viewport_height, "поле ввода должно быть видно при открытии"
    assert_operator air, :>=, 24, "поле ввода не должно липнуть к низу экрана"
    assert_operator composer_gap, :>=, 12, "полю ввода нужен отступ от ленты"
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

    def thread_gap
      page.evaluate_script(THREAD_GAP).to_f
    end

    # [top, bottom, air below the composer]
    def composer
      page.evaluate_script(COMPOSER).map(&:to_f)
    end

    def viewport_height
      page.evaluate_script("window.innerHeight").to_f
    end

    def composer_gap
      page.evaluate_script(
        "document.querySelector('.qf-chatbar').getBoundingClientRect().top - " \
        "document.getElementById('comments').getBoundingClientRect().bottom"
      ).to_f
    end
end
