class MyQuestionsController < ApplicationController
  def show
    @questions = Current.user.authored_questions.includes(:attempts).order(:deadline)
  end
end
