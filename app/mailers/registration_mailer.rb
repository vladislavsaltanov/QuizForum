class RegistrationMailer < ApplicationMailer
  # Email-ownership confirmation.
  def confirmation(user)
    @user = user
    mail subject: "Подтвердите почту", to: user.email
  end
end
