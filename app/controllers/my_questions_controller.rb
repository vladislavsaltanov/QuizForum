# Dashboard: questions the user authored plus ones they observe as trustee.
class MyQuestionsController < ApplicationController
  # Loads authored and trustee questions, earliest deadline first.
  def show
    @questions = Current.user.authored_questions.includes(:attempts).order(:deadline)
    @trustee_questions = Current.user.trusted_questions.includes(:author, :attempts).order(:deadline)
  end
end
