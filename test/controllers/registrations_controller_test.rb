require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "new" do
    get new_registration_path
    assert_response :success
  end

  test "create with valid params creates unconfirmed user and sends confirmation mail" do
    assert_difference("User.count") do
      post registrations_path, params: { user: { name: "New", email: "new@example.com", password: "password-12-plus", password_confirmation: "password-12-plus" } }
    end

    assert_redirected_to sent_confirmations_path
    assert_nil cookies[:session_id]
    assert_enqueued_email_with RegistrationMailer, :confirmation
  end

  test "create with invalid params renders new" do
    assert_no_difference("User.count") do
      post registrations_path, params: { user: { name: "", email: "bad", password: "x", password_confirmation: "y" } }
    end

    assert_response :unprocessable_entity
  end
end
