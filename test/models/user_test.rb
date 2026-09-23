require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email" do
    user = User.new(email: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email)
  end

  test "requires name" do
    assert_not User.new(email: "a@example.com", password: "password-12-plus").valid?
  end

  test "rejects short passwords" do
    user = User.new(name: "Short", email: "short@example.com", password: "short", password_confirmation: "short")
    assert_not user.valid?
    assert_includes user.errors[:password], "is too short (minimum is 12 characters)"
  end

  test "confirmed? reflects email_confirmed_at" do
    assert users(:one).confirmed?
    assert_not User.new.confirmed?
  end

  test "find_or_create_by_omniauth creates a new user from auth hash" do
    auth = omniauth_hash(provider: "google_oauth2", uid: "123", name: "OAuth", email: "oauth@example.com")

    assert_difference("User.count") do
      user = User.find_or_create_by_omniauth(auth)
      assert_equal "oauth@example.com", user.email
      assert_equal "google_oauth2", user.provider
    end
  end

  test "find_or_create_by_omniauth adopts an existing user by email" do
    existing = users(:one)

    user = User.find_or_create_by_omniauth(omniauth_hash(provider: "google_oauth2", uid: "999", name: existing.name, email: existing.email))

    assert_equal existing.id, user.id
    assert_equal "google_oauth2", user.reload.provider
    assert_equal "999", user.uid
  end

  test "find_or_create_by_omniauth returns existing oauth user" do
    first = User.find_or_create_by_omniauth(omniauth_hash(provider: "google_oauth2", uid: "555", name: "Repeat", email: "repeat@example.com"))

    assert_no_difference("User.count") do
      second = User.find_or_create_by_omniauth(omniauth_hash(provider: "google_oauth2", uid: "555", name: "Repeat", email: "repeat@example.com"))
      assert_equal first.id, second.id
    end
  end

  test "find_or_create_by_omniauth normalizes provider email before lookup" do
    existing = users(:one)

    user = User.find_or_create_by_omniauth(omniauth_hash(provider: "google_oauth2", uid: "888", name: existing.name, email: "  #{existing.email.upcase} "))

    assert_equal existing.id, user.id
  end

  test "rejects toxic name from moderation" do
    ModerationClient.define_singleton_method(:check) do |*_, **_|
      ModerationClient::Result.new(:reject, "оскорбление")
    end
    user = User.new(name: "Токсичный", email: "tox@example.com", password: "password-12-plus")

    assert_not user.valid?
  end

  test "rejects duplicate name case-insensitively" do
    ModerationClient.define_singleton_method(:check) do |*_, **_|
      ModerationClient::Result.new(:pass, "")
    end
    user = User.new(name: users(:one).name.upcase, email: "dup@example.com", password: "password-12-plus")

    assert_not user.valid?
    assert_includes user.errors[:name], "has already been taken"
  end

  private
    def omniauth_hash(provider:, uid:, name:, email:)
      OmniAuth::AuthHash.new(provider: provider, uid: uid, info: { name: name, email: email })
    end
end
