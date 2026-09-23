module ApplicationCable
  # Cable identity from the session cookie; guests never connect.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    # Rejects guests, identifies users.
    def connect
      set_current_user || reject_unauthorized_connection
    end

    private
      # User behind the signed cookie, if any.
      def set_current_user
        if session = Session.find_by(id: cookies.signed[:session_id])
          self.current_user = session.user
        end
      end
  end
end
