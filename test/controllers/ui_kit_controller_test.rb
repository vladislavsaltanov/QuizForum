require "test_helper"

class UiKitControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
  end

  test "guest is redirected to sign in" do
    sign_out
    get ui_kit_path

    assert_redirected_to new_session_path
  end

  test "showcases components with captions" do
    get ui_kit_path

    assert_response :success
    assert_select "h1.qf-hero", text: "UI-кит"
    assert_select ".qf-swatch", minimum: 7
    assert_select "h2.qf-section-title", minimum: 8
    assert_select ".qf-chip.qf-verdict-correct", text: "Правильно"
    assert_select ".qf-chip.qf-verdict-partial", text: "Почти, но нет"
    assert_select ".qf-chip.qf-verdict-incorrect", text: "Неправильно"
    assert_select ".qf-chip.qf-verdict-pending", text: "На проверке"
    assert_select ".qf-card .qf-card-title"
    assert_select ".qf-stat b.qf-verdict-correct"
    assert_select ".qf-avatar-xl"
    assert_select ".qf-bubble p"
    assert_select ".qf-notice"
    assert_select ".qf-alert"
  end

  test "has no nav link to itself" do
    get root_path

    assert_select 'a[href="/ui-kit"]', count: 0
  end
end
