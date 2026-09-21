require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "new redirects signed-in users to root" do
    sign_in_as(@user)

    get new_session_path

    assert_redirected_to root_path
  end

  test "create with valid credentials" do
    post session_path, params: { email: @user.email, password: "password-12-plus" }

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post session_path, params: { email: @user.email, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "create with unconfirmed email redirects to confirmation" do
    User.create!(name: "Un", email: "unconfirmed-login@example.com",
      password: "password-12-plus", password_confirmation: "password-12-plus")

    post session_path, params: { email: "unconfirmed-login@example.com", password: "password-12-plus" }

    assert_redirected_to new_confirmation_path
    assert_nil cookies[:session_id]
  end

  test "destroy" do
    sign_in_as(User.take)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end

  test "google_oauth2 creates user from auth hash and signs in" do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "777",
      info: { name: "Google", email: "google@example.com" },
      extra: { raw_info: { email_verified: true } }
    )

    assert_difference("User.count") do
      post "/auth/google_oauth2/callback"
    end

    assert_redirected_to root_path
    assert cookies[:session_id]
  ensure
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  test "google_oauth2 rejects unverified email" do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "778",
      info: { name: "Unverified", email: "unverified@example.com" },
      extra: { raw_info: { email_verified: false } }
    )

    assert_no_difference("User.count") do
      post "/auth/google_oauth2/callback"
    end

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  ensure
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  test "omniauth_failure redirects to sign in" do
    get "/auth/failure"

    assert_redirected_to new_session_path
  end

  test "google_oauth2 without auth hash fails safely to sign in" do
    post "/auth/google_oauth2/callback"
    assert_redirected_to %r{/auth/failure}

    follow_redirect!
    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "authenticated page redirects unauthenticated visitor to sign in" do
    sign_out
    get edit_password_path("anything")

    assert_redirected_to new_password_path
  end
end
