require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "guest is redirected to sign in" do
    get root_path

    assert_redirected_to new_session_path
  end

  test "shows email, registration time and sign out" do
    user = users(:one)
    sign_in_as(user)
    get root_path

    assert_response :success
    assert_select "p", text: /Signed in as #{Regexp.escape(user.email)}/
    assert_select "time[datetime=?]", user.created_at.iso8601
    assert_select "form[action=?]", session_path do
      assert_select "input[name=?][value=?]", "_method", "delete"
      assert_select "button", text: "Sign out"
    end
  end
end
