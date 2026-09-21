require "test_helper"

class ConfirmationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Unconfirmed", email: "unconfirmed@example.com",
      password: "password-12-plus", password_confirmation: "password-12-plus")
  end

  test "new" do
    get new_confirmation_path
    assert_response :success
  end

  test "create enqueues confirmation mail and redirects" do
    post confirmations_path, params: { email: @user.email }
    assert_enqueued_email_with RegistrationMailer, :confirmation, args: [ @user ]
    assert_redirected_to sent_confirmations_path
  end

  test "create for an unknown email redirects the same but sends no mail" do
    post confirmations_path, params: { email: "missing-user@example.com" }
    assert_enqueued_emails 0
    assert_redirected_to sent_confirmations_path
  end

  test "create skips mail for already confirmed users" do
    assert_enqueued_emails 0 do
      post confirmations_path, params: { email: users(:one).email }
    end
    assert_redirected_to sent_confirmations_path
  end

  test "sent explains the email without leaking user existence" do
    get sent_confirmations_path
    assert_response :success
  end

  test "accept confirms the user and signs in" do
    get accept_confirmation_path(@user.email_confirmation_token)

    assert @user.reload.confirmed?
    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "accept with invalid token redirects with alert" do
    get accept_confirmation_path("invalid token")
    assert_redirected_to new_confirmation_path

    follow_redirect!
    assert_match(/invalid|expired/i, response.body)
  end
end
