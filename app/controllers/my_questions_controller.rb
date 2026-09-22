class MyQuestionsController < ApplicationController
  def show
    @questions = Current.user.authored_questions.includes(:attempts).order(:deadline)
    @trustee_questions = Current.user.trusted_questions.includes(:author, :attempts).order(:deadline)
  end
end
