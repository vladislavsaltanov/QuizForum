# Password reset via an emailed token link.
class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_password_path, alert: "Try again later." }

  # Renders the forgot-password form.
  def new
  end

  # Sends the reset email; always redirects alike so addresses stay unguessable.
  def create
    if user = User.find_by(email: params[:email])
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to sent_passwords_path
  end

  # Renders the reset-email-sent notice.
  def sent
  end

  # Renders the new-password form for a valid token.
  def edit
  end

  # Sets the new password and kills all other sessions.
  def update
    if @user.update(params.permit(:password, :password_confirmation))
      @user.sessions.destroy_all
      redirect_to new_session_path, notice: "Password has been reset."
    else
      redirect_to edit_password_path(params[:token]), alert: "Passwords did not match."
    end
  end

  private
    # Loads the user from the reset token; bad or expired links bounce to a new request.
    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
    end
end
