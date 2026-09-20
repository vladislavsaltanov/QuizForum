require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "guest is redirected to sign in" do
    sign_out
    get profile_path

    assert_redirected_to new_session_path
  end

  test "shows identity, stats and rank" do
    Attempt.create!(question: questions(:closed_single), user: users(:one), selected: [ "0" ])
    Attempt.create!(question: questions(:closed_text), user: users(:one), body: "x", verdict: "correct")
    Attempt.create!(question: questions(:open_text), user: users(:one), body: "y")
    get profile_path

    assert_response :success
    assert_select "h1.qf-hero", text: "One"
    assert_select ".qf-id-card", text: /one@example\.com/
    assert_select ".qf-stat", text: /Опубликовано вопросов/
    assert_select ".qf-stat", text: /Дано ответов/
    assert_select ".qf-stat", text: /Верных ответов/
    assert_select ".qf-id-card .qf-chip", text: "#1 в рейтинге"
  end

  test "scoreless user sees dash" do
    get profile_path

    assert_select ".qf-id-card .qf-chip", text: "#- вне таблицы"
  end

  test "guest is redirected from edit and update" do
    sign_out
    get edit_profile_path

    assert_redirected_to new_session_path

    patch profile_path, params: { user: { name: "X" } }

    assert_redirected_to new_session_path
  end

  test "updates name but never display role" do
    @user.update!(display_role: "аспирант")
    patch profile_path, params: { user: { name: "Иван", display_role: "ректор" } }

    assert_redirected_to profile_path
    @user.reload
    assert_equal "Иван", @user.name
    assert_equal "аспирант", @user.display_role
  end

  test "rejects blank name without touching email" do
    patch profile_path, params: { user: { name: "", display_role: "x", email: "evil@example.com" } }

    assert_response :unprocessable_entity
    assert_equal "one@example.com", @user.reload.email
  end

  test "changes email with current password" do
    patch profile_path, params: { user: { name: "One", email: "new@example.com", current_password: "password" } }

    assert_redirected_to profile_path
    assert_equal "new@example.com", @user.reload.email
  end

  test "rejects email change with wrong password" do
    patch profile_path, params: { user: { name: "One", email: "evil@example.com", current_password: "nope" } }

    assert_response :unprocessable_entity
    assert_equal "one@example.com", @user.reload.email
  end

  test "changes password and kills other sessions" do
    @user.sessions.create!
    patch profile_path, params: { user: { name: "One", password: "newpassword123", password_confirmation: "newpassword123", current_password: "password" } }

    assert_redirected_to profile_path
    assert @user.reload.authenticate("newpassword123")
    assert_equal 1, @user.sessions.count
  end

  test "rejects password change without current password" do
    patch profile_path, params: { user: { name: "One", password: "newpassword123", password_confirmation: "newpassword123" } }

    assert_response :unprocessable_entity
    assert @user.reload.authenticate("password")
  end

  test "oauth user changes email without current password" do
    oauth = User.create!(name: "Oa", email: "oa@example.com", provider: "google_oauth2", uid: "1",
      password: "password12345678", password_confirmation: "password12345678")
    sign_in_as(oauth)
    patch profile_path, params: { user: { name: "Oa", email: "oa2@example.com" } }

    assert_redirected_to profile_path
    assert_equal "oa2@example.com", oauth.reload.email
  end

  test "duplicate email renders edit" do
    patch profile_path, params: { user: { name: "One", email: "two@example.com", current_password: "password" } }

    assert_response :unprocessable_entity
    assert_equal "one@example.com", @user.reload.email
  end
end
