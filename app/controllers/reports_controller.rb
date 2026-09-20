class ReportsController < ApplicationController
  def create
    @question = Question.find(params[:question_id])
    @question.reports.find_or_create_by!(user: Current.user)
    redirect_to @question, notice: "Жалоба отправлена."
  end
end
