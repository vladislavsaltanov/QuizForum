# Landing: searchable, filterable question index.
class HomeController < ApplicationController
  include Paginates
  include FiltersQuestions

  # Collects filter params and the filtered question list for the index view.
  # The AI pack lives behind its own banner above the list, never inside it —
  # unless the browser asked to hide it via the profile cookie.
  def show
    @user = Current.user
    @questions = paginate(filter_questions(Question.feed.human)).includes(:author, :attempts)
    @ai_pack = cookies[:hide_ai_banner] == "1" ? [] : Question.latest_ai_pack
  end
end
