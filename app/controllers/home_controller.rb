# Landing: searchable, filterable question index.
class HomeController < ApplicationController
  # Collects filter params and the filtered question list for the index view.
  def show
    @user = Current.user
    @q = params[:q].to_s.strip
    @author = params[:author].to_s
    @difficulty = params[:difficulty].to_s
    @topic = params[:topic].to_s
    @authors = User.joins(:authored_questions).distinct.order(:name).pluck(:name)
    @topics = (Question.pluck(:tags).flatten.uniq - Question::DIFFICULTIES).sort
    @questions = filter_questions.includes(:author)
  end

  private
    # Narrows questions by text, author, difficulty, topic; empty filters are skipped.
    def filter_questions
      scope = Question.order(:id)
      scope = scope.where("title ILIKE ?", "%#{@q}%") if @q.present?
      scope = scope.joins(:author).where(users: { name: @author }) if @author.present?
      scope = scope.where("? = ANY (tags)", @difficulty) if @difficulty.present?
      scope = scope.where("? = ANY (tags)", @topic) if @topic.present?
      scope
    end
end
