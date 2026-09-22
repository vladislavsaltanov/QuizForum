# Email confirmation: resend form and token acceptance.
class ConfirmationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_confirmation_path, alert: "Try again later." }

  # Renders the resend-confirmation form.
  def new
  end

  # Resends the confirmation email; stays silent for unknown or confirmed addresses.
  def create
    if user = User.find_by(email: params[:email])
      RegistrationMailer.confirmation(user).deliver_later unless user.confirmed?
    end

    redirect_to sent_confirmations_path
  end

  # Renders the confirmation-email-sent notice.
  def sent
  end

  # Confirms the email from the token link and signs the user in.
  def accept
    user = User.find_by_email_confirmation_token!(params[:token])
    user.update!(email_confirmed_at: Time.current)
    start_new_session_for user
    redirect_to root_path, notice: "Почта подтверждена."
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_to new_confirmation_path, alert: "Ссылка недействительна или истекла."
  end
end
