# Shared q/author/difficulty/topic narrowing for the question lists (feed and archive).
module FiltersQuestions
  extend ActiveSupport::Concern

  private
    # Reads the filter params into instance variables and narrows the scope.
    # The dropdown options come from the same base scope the list is built from,
    # so an option can never lead to a result page with nothing in it.
    def filter_questions(scope)
      @q = params[:q].to_s.strip
      @author = params[:author].to_s
      @difficulty = params[:difficulty].to_s
      @topic = params[:topic].to_s
      @authors = User.where(id: scope.select(:author_id)).order(:name).pluck(:name)
      @topics = (scope.unscope(:order).pluck(:tags).flatten.uniq - Question::DIFFICULTIES).sort
      scope = scope.where("title ILIKE ?", "%#{@q}%") if @q.present?
      scope = scope.joins(:author).where(users: { name: @author }) if @author.present?
      scope = scope.where("? = ANY (tags)", @difficulty) if @difficulty.present?
      scope = scope.where("? = ANY (tags)", @topic) if @topic.present?
      scope
    end
end
