require "application_system_test_case"

class CommentScrollTest < ApplicationSystemTestCase
  # The pane prepends older comments asynchronously; give the fetch room.
  def setup
    Capybara.default_max_wait_time = 5
    super
  end

  test "scrolling the chat up prepends the next ten comments" do
    question = questions(:open_text)
    25.times { |i| question.comments.create!(user: users(:two), body: "Комментарий #{i}", status: "approved") }

    visit new_session_url
    fill_in "email", with: "one@example.com"
    fill_in "password", with: "password-12-plus"
    click_on "Войти"
    visit question_url(question, tab: "comments")

    assert_selector "#comments .qf-msg", count: 10

    scroll_chat_to_top
    assert_selector "#comments .qf-msg", count: 20

    scroll_chat_to_top
    assert_selector "#comments .qf-msg", count: 25

    # Nothing older left, so the marker is gone and a third scroll fetches nothing.
    assert_no_selector "#comments-more"
  end

  private
    # The scroll event is dispatched explicitly so the check does not depend on
    # whether the ten visible bubbles happen to overflow the pane.
    def scroll_chat_to_top
      find("#comments").evaluate_script(
        "el => { el.scrollTop = 0; el.dispatchEvent(new Event('scroll')); }"
      )
    end
end
