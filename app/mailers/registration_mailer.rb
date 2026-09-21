class RegistrationMailer < ApplicationMailer
  def confirmation(user)
    @user = user
    mail subject: "Подтвердите почту", to: user.email
  end
end
