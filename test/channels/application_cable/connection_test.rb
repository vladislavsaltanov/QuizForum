require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects with valid session" do
    session = users(:one).sessions.create!
    cookies.signed[:session_id] = session.id

    connect

    assert_equal users(:one), connection.current_user
  end

  test "rejects without session" do
    assert_reject_connection { connect }
  end
end
