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
    # One query for the respondent marks: id presence drives the pre-Deadline
    # plaque, verdict drives the post-Deadline dot. Never loads others' state.
    @solved = Attempt.where(user: Current.user, question_id: @questions.map(&:id)).pluck(:question_id, :verdict).to_h
    @ai_pack = cookies[:hide_ai_banner] == "1" ? [] : Question.latest_ai_pack
    # Licensed home feed: strangers' published open unguarded tests only.
    @feed_tests = Test.home_feed.where.not(author: @user).includes(:author, :questions).limit(6)
  end
end
