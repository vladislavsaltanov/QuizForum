class TrusteesController < ApplicationController
  before_action :set_question

  def create
    return head(:forbidden) unless manager?
    user = User.find_by(email: params[:email].to_s.strip.downcase)
    grant = @question.question_trustees.build(user: user) if user
    if user && grant.save
      redirect_to @question, notice: "Наблюдатель добавлен."
    elsif user.nil?
      redirect_to @question, alert: "Пользователь не найден."
    else
      redirect_to @question, alert: grant.errors.full_messages.to_sentence
    end
  end

  def destroy
    return head(:forbidden) unless manager?
    @question.question_trustees.find(params[:id]).destroy!
    redirect_to @question, notice: "Доступ наблюдателя отозван."
  end

  private
    def set_question
      @question = Question.find(params[:question_id])
    end

    # ponytail: grant management is author-or-admin only; trustees never manage
    def manager?
      @question.author == Current.user || Current.user&.admin?
    end
end
