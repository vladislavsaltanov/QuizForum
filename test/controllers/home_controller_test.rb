require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "guest is redirected to sign in" do
    get root_path

    assert_redirected_to new_session_path
  end

  test "shows email, registration time and sign out" do
    sign_in_as(users(:one))
    get root_path

    assert_response :success
    assert_match users(:one).email, response.body
    assert_select "time"
    assert_select "form[action=?]", session_path
  end
end
