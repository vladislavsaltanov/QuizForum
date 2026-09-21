require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_password_path
    assert_response :success
  end

  test "create" do
    post passwords_path, params: { email: @user.email }
    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
    assert_redirected_to sent_passwords_path

    follow_redirect!
    assert_select "h1", "Проверьте почту"
  end

  test "create for an unknown user redirects but sends no mail" do
    post passwords_path, params: { email: "missing-user@example.com" }
    assert_enqueued_emails 0
    assert_redirected_to sent_passwords_path

    follow_redirect!
    assert_select "h1", "Проверьте почту"
  end

  test "sent explains the email without leaking user existence" do
    get sent_passwords_path

    assert_response :success
    assert_match(/Если пользователь с таким адресом существует/, response.body)
  end

  test "edit" do
    get edit_password_path(@user.password_reset_token)
    assert_response :success
  end

  test "edit with invalid password reset token" do
    get edit_password_path("invalid token")
    assert_redirected_to new_password_path

    follow_redirect!
    assert_notice "reset link is invalid"
  end

  test "update" do
    assert_changes -> { @user.reload.password_digest } do
      put password_path(@user.password_reset_token), params: { password: "new-password-12", password_confirmation: "new-password-12" }
      assert_redirected_to new_session_path
    end

    follow_redirect!
    assert_notice "Password has been reset"
  end

  test "update with non matching passwords" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "no", password_confirmation: "match" }
      assert_redirected_to edit_password_path(token)
    end

    follow_redirect!
    assert_notice "Passwords did not match"
  end

  private
    def assert_notice(text)
      assert_select "div", /#{text}/
    end
end
