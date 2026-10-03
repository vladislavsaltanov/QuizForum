require "application_system_test_case"

# The browser anchors the <input type=datetime-local> step grid to the seconds it loaded.
# Zeroing them in the form's timezone script left the field step-invalid: Chrome refused
# to submit the edit form at all and offered 10:37:22 / 10:38:22 as the nearest legal values.
class QuestionDeadlineEditTest < ApplicationSystemTestCase
  test "edit form submits when the stored deadline carries seconds" do
    question = questions(:open_text)
    question.update_column(:deadline, 7.days.from_now.change(sec: 22))
    sign_in_through_ui

    visit edit_question_path(question)
    fill_in "Заголовок", with: "Правка с дедлайном"
    click_button "Сохранить"

    assert_current_path question_path(question)
    assert_equal "Правка с дедлайном", question.reload.title
    assert_equal 22, question.deadline.sec, "seconds must survive the timezone round trip"
  end

  private
    def sign_in_through_ui
      visit new_session_url
      fill_in "email", with: "one@example.com"
      fill_in "password", with: "password-12-plus"
      click_on "Войти"
      assert_current_path root_path
    end
end
