require "test_helper"

class ErrorsControllerTest < ActionDispatch::IntegrationTest
  test "unknown page renders site-styled 404 with home link" do
    get "/404"

    assert_response :not_found
    assert_select "h1.qf-hero", text: "Такой страницы нет"
    assert_select "a.qf-apply[href=?]", root_path, text: "На главный экран"
  end
end
