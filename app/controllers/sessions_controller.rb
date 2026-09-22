# Email + Google sign-in and sign-out.
class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create google_oauth2 omniauth_failure ]
  rate_limit to: 10, within: 3.minutes, only: %i[ create google_oauth2 ], with: -> { redirect_to new_session_path, alert: "Try again later." }
  before_action :redirect_if_authenticated, only: :new

  # Renders the sign-in form.
  def new
  end

  # Signs in by email/password; unconfirmed accounts must confirm first.
  def create
    if user = User.authenticate_by(params.permit(:email, :password))
      if user.confirmed?
        start_new_session_for user
        redirect_to after_authentication_url
      else
        redirect_to new_confirmation_path, alert: "Подтвердите почту — мы отправили вам письмо со ссылкой."
      end
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  # Signs out of the current session.
  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end

  # Signs in via Google; requires a verified email.
  def google_oauth2
    auth = request.env["omniauth.auth"]
    unless auth&.uid.present? && auth.info.email.present? &&
        auth.dig(:extra, :raw_info, :email_verified) == true
      return redirect_to new_session_path, alert: "Authentication failed. Try again."
    end

    user = User.find_or_create_by_omniauth(auth)
    start_new_session_for user
    redirect_to after_authentication_url
  end

  # Handles cancelled or failed Google sign-in.
  def omniauth_failure
    redirect_to new_session_path, alert: "Authentication failed. Try again."
  end
end
