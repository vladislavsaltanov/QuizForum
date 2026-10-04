# Landing: searchable, filterable question index.
class HomeController < ApplicationController
  include Paginates
  include FiltersQuestions

  # Collects filter params and the filtered question list for the index view.
  def show
    @user = Current.user
    @questions = paginate(filter_questions(Question.feed)).includes(:author, :attempts)
  end
end
