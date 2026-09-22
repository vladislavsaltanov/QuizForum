class PasswordsMailer < ApplicationMailer
  # Password-reset email.
  def reset(user)
    @user = user
    mail subject: "Reset your password", to: user.email
  end
end
