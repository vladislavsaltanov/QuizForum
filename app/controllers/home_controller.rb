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
    # Отметка «решено» на тестовых плашках: одна выборка попыток
    # зрителя по всем вопросам ленты, без N+1.
    @my_test_state = {}
    if @feed_tests.any?
      ids = @feed_tests.flat_map(&:question_ids)
      mine = Attempt.where(user: Current.user, question_id: ids).index_by(&:question_id)
      @feed_tests.each do |test|
        @my_test_state[test.id] = true if test.questions.any? { mine.key?(it.id) }
      end
    end
  end
end
