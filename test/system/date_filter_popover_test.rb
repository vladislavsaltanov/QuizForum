require "application_system_test_case"

class DateFilterPopoverTest < ApplicationSystemTestCase
  test "date range opens in one compact filter dialog" do
    visit new_session_url
    fill_in "email", with: "one@example.com"
    fill_in "password", with: "password-12-plus"
    click_on "Войти"

    assert_current_path root_path
    assert_selector "button.qf-filter[popovertarget='qf-date-range']", text: "Дата"
    click_button "Дата"

    assert_selector "#qf-date-range[role=dialog]", visible: true do
      assert_selector "input[type=date]", count: 2
    end

    click_button "Закрыть"
    assert_no_selector "#qf-date-range[role=dialog]", visible: true
  end
end
