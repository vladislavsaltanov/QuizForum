# One-click abuse reports, at most one per user per question.
class ReportsController < ApplicationController
  # Records the current user's report; repeats collapse into the same row.
  def create
    @question = Question.find(params[:question_id])
    @question.reports.find_or_create_by!(user: Current.user)
    redirect_to @question, notice: "Жалоба отправлена."
  end
end
