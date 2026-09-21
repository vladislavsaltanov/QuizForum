class ConfirmationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_confirmation_path, alert: "Try again later." }

  def new
  end

  def create
    if user = User.find_by(email: params[:email])
      RegistrationMailer.confirmation(user).deliver_later unless user.confirmed?
    end

    redirect_to sent_confirmations_path
  end

  def sent
  end

  def accept
    user = User.find_by_email_confirmation_token!(params[:token])
    user.update!(email_confirmed_at: Time.current)
    start_new_session_for user
    redirect_to root_path, notice: "Почта подтверждена."
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_to new_confirmation_path, alert: "Ссылка недействительна или истекла."
  end
end
