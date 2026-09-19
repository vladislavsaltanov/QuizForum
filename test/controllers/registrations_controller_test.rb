require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "new" do
    get new_registration_path
    assert_response :success
  end

  test "create with valid params creates user and signs in" do
    assert_difference("User.count") do
      post registrations_path, params: { user: { name: "New", email: "new@example.com", password: "password", password_confirmation: "password" } }
    end

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "create with invalid params renders new" do
    assert_no_difference("User.count") do
      post registrations_path, params: { user: { name: "", email: "bad", password: "x", password_confirmation: "y" } }
    end

    assert_response :unprocessable_entity
  end
end
