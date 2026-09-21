require "test_helper"

class DisplayRoleTest < ActionDispatch::IntegrationTest
  setup do
    @author = users(:one) # author of open_text
    @question = questions(:open_text)
    sign_in_as(@author)
  end

  test "comment shows display_role after name via bold middot" do
    users(:two).update!(display_role: "доцент кафедры")
    comment = Comment.create!(question: @question, user: users(:two), body: "когда дедлайн?")
    get question_path(@question, tab: "comments")

    assert_response :success
    assert_select "#comment_#{comment.id} .qf-msg-head", text: /Two/
    assert_select "#comment_#{comment.id} .qf-msg-head", text: /доцент кафедры/
    assert_match(/Two<.*<b[^>]*>·<\/b> доцент кафедры/m, response.body)
  end

  test "comment without role shows no middot" do
    comment = Comment.create!(question: @question, user: users(:two), body: "когда дедлайн?")
    get question_path(@question, tab: "comments")

    assert_response :success
    assert_select "#comment_#{comment.id} .qf-msg-head b.qf-dot", count: 0
  end

  test "malicious display_role is escaped in comments" do
    users(:two).update!(display_role: "<script>alert(1)</script>")
    Comment.create!(question: @question, user: users(:two), body: "hi")
    get question_path(@question, tab: "comments")

    assert_response :success
    assert_no_match(/<script>alert\(1\)<\/script>/, response.body)
    assert_match(/&lt;script&gt;alert\(1\)&lt;\/script&gt;/, response.body)
  end

  test "profile shows user id" do
    get profile_path

    assert_response :success
    assert_select ".qf-id-card", text: /ID #{@author.id}/
  end

  test "non-admin sees no grant panel" do
    get profile_path

    assert_response :success
    assert_select "form[action=?]", grant_role_profile_path, count: 0
  end

  test "admin sees grant panel" do
    sign_in_as(admin_user)
    get profile_path

    assert_response :success
    assert_select "form[action=?]", grant_role_profile_path, count: 1
  end

  test "stranger cannot grant roles" do
    patch grant_role_profile_path, params: { user_id: users(:two).id, display_role: "ректор" }

    assert_response :forbidden
    assert_nil users(:two).reload.display_role
  end

  test "guest is redirected from grant endpoint" do
    sign_out
    patch grant_role_profile_path, params: { user_id: users(:two).id, display_role: "ректор" }

    assert_redirected_to new_session_path
    assert_nil users(:two).reload.display_role
  end

  test "admin grants role with stripped whitespace" do
    sign_in_as(admin_user)
    patch grant_role_profile_path, params: { user_id: users(:two).id, display_role: "  доцент кафедры  " }

    assert_redirected_to profile_path
    assert_equal "доцент кафедры", users(:two).reload.display_role
  end

  test "admin grant rejects unknown id without crash" do
    sign_in_as(admin_user)
    patch grant_role_profile_path, params: { user_id: 999_999, display_role: "ректор" }

    assert_redirected_to profile_path
    follow_redirect!
    assert_select ".qf-alert", text: /не найден/
  end

  test "admin grant rejects too-long role, accepts 50 chars" do
    sign_in_as(admin_user)
    patch grant_role_profile_path, params: { user_id: users(:two).id, display_role: "x" * 51 }

    assert_redirected_to profile_path
    assert_nil users(:two).reload.display_role

    patch grant_role_profile_path, params: { user_id: users(:two).id, display_role: "x" * 50 }

    assert_redirected_to profile_path
    assert_equal "x" * 50, users(:two).reload.display_role
  end

  test "blank role clears display_role" do
    users(:two).update!(display_role: "доцент")
    sign_in_as(admin_user)
    patch grant_role_profile_path, params: { user_id: users(:two).id, display_role: "   " }

    assert_redirected_to profile_path
    assert_nil users(:two).reload.display_role
  end

  test "grant touches only display_role" do
    sign_in_as(admin_user)
    patch grant_role_profile_path, params: { user_id: users(:two).id,
      display_role: "аспирант", name: "Hacked", admin: true }

    two = users(:two).reload
    assert_equal "аспирант", two.display_role
    assert_equal "Two", two.name
    assert_equal false, two.admin?
  end

  private
    def admin_user
      User.create!(name: "RoleAdmin", email: "role-admin@example.com",
        password: "password12345678", password_confirmation: "password12345678",
        admin: true, display_role: "администратор")
    end
end
