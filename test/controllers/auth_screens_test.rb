require "test_helper"

class AuthScreensTest < ActionDispatch::IntegrationTest
  test "sign in shows Google button and auth links" do
    get new_session_path

    assert_response :success
    assert_select "h1.qf-hero", text: "Вход"
    assert_select 'form[action="/auth/google_oauth2"]'
    assert_select "a[href=?]", new_password_path
    assert_select "a[href=?]", new_registration_path
  end

  test "sign up shows Google button and sign in link" do
    get new_registration_path

    assert_response :success
    assert_select "h1.qf-hero", text: "Регистрация"
    assert_select 'form[action="/auth/google_oauth2"]'
    assert_select "a[href=?]", new_session_path
  end
end
