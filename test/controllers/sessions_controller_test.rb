require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email: @user.email, password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post session_path, params: { email: @user.email, password: "wrong" }

    assert_redirected_to new_session_path
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
      provider: "google_oauth2", uid: "777", info: { name: "Google", email: "google@example.com" }
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

  test "omniauth_failure redirects to sign in" do
    get "/auth/failure"

    assert_redirected_to new_session_path
  end

  test "google_oauth2 without auth hash fails safely to sign in" do
    post "/auth/google_oauth2/callback"
    assert_redirected_to %r{/auth/failure}

    follow_redirect!
    assert_redirected_to new_session_path
  end
end
