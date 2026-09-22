class TrusteesController < ApplicationController
  before_action :set_question

  def create
    return head(:forbidden) unless manager?
    ok, message = @question.grant_trustee_by_email(params[:email])
    if ok
      redirect_to @question, notice: "Наблюдатель добавлен."
    else
      redirect_to @question, alert: message
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
