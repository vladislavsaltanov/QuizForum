class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  before_action :redirect_if_authenticated, only: :new

  def new
    @user = User.new
  end

  def create
    @user = User.new(params.expect(user: [ :name, :email, :password, :password_confirmation ]))
    if @user.save
      RegistrationMailer.confirmation(@user).deliver_later
      redirect_to sent_confirmations_path
    else
      render :new, status: :unprocessable_entity
    end
  end
end
