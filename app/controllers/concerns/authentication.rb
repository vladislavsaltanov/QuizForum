# Cookie sessions: every action needs sign-in unless opted out.
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    # Opens listed actions to guests.
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    # True with a live session.
    def authenticated?
      resume_session
    end

    # Sends guests to sign-in.
    def require_authentication
      resume_session || request_authentication
    end

    # Signed-in visitors skip sign-in pages.
    def redirect_if_authenticated
      redirect_to root_url if authenticated?
    end

    # Picks up the session from the cookie once per request.
    def resume_session
      Current.session ||= find_session_by_cookie
    end

    # Session row for the signed cookie, if any.
    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    # Stashes the URL and redirects to sign-in.
    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    # Stashed URL or home.
    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    # Creates the session row and permanent cookie.
    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    # Destroys the session and drops the cookie.
    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
