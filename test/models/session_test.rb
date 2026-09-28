require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "requires user" do
    assert_not Session.new.valid?
  end

  test "belongs to user" do
    session = Session.create!(user: users(:one))

    assert_equal users(:one), session.user
  end
end
