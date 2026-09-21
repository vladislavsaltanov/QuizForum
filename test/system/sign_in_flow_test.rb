require "application_system_test_case"

class SignInFlowTest < ApplicationSystemTestCase
  test "signing in with valid credentials" do
    visit new_session_url

    fill_in "email", with: "one@example.com"
    fill_in "password", with: "password-12-plus"
    click_on "Войти"

    assert_current_path root_path
  end
end
