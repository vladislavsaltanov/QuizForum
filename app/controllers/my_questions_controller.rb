# Dashboard: questions the user authored plus ones they observe as trustee.
# Test-scoped questions live only inside their test, never here.
class MyQuestionsController < ApplicationController
  include Paginates

  # Loads authored and trustee questions, earliest deadline first.
  def show
    @questions = paginate(Current.user.authored_questions.standalone.order(:deadline)).includes(:attempts)
    @trustee_questions = paginate(Current.user.trusted_questions.order(:deadline), key: :t_page)
      .includes(:author, :attempts)
  end
end
