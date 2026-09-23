require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "new" do
    get new_registration_path
    assert_response :success
  end

  test "new redirects signed-in users to root" do
    sign_in_as(users(:one))

    get new_registration_path

    assert_redirected_to root_path
  end

  test "create with valid params creates unconfirmed user and sends confirmation mail" do
    assert_difference("User.count") do
      post registrations_path, params: { user: { name: "New", email: "new@example.com", password: "password-12-plus", password_confirmation: "password-12-plus" } }
    end

    assert_redirected_to sent_confirmations_path
    assert_nil cookies[:session_id]
    assert_enqueued_email_with RegistrationMailer, :confirmation, args: [ User.find_by!(email: "new@example.com") ]
  end

  test "create with invalid params renders new" do
    assert_no_difference("User.count") do
      post registrations_path, params: { user: { name: "", email: "bad", password: "x", password_confirmation: "y" } }
    end

    assert_response :unprocessable_entity
  end

  test "duplicate name race renders taken instead of 500" do
    User.create!(name: "Занято", email: "taken-race@example.com",
                 password: "password-12-plus", password_confirmation: "password-12-plus")
    original = ActiveRecord::Relation.instance_method(:exists?)
    ActiveRecord::Relation.define_method(:exists?) { |*_| false }
    begin
      assert_no_difference("User.count") do
        post registrations_path, params: { user: { name: "занято", email: "fresh-race@example.com",
          password: "password-12-plus", password_confirmation: "password-12-plus" } }
      end
    ensure
      ActiveRecord::Relation.define_method(:exists?, original)
    end

    assert_response :unprocessable_entity
  end
end
