# Shared filters for the Home and Archive question lists.
module FiltersQuestions
  extend ActiveSupport::Concern

  private
    # Reads filter params and narrows the given base scope; every filter stays
    # inside it, so archived Questions only ever appear on the Archive page.
    def filter_questions(scope)
      @q = params[:q].to_s.strip
      @author = params[:author].to_s
      @difficulty = params[:difficulty].to_s
      @topic = params[:topic].to_s
      @date_filter_error = false
      @date_from = parse_filter_date(:date_from)
      @date_to = parse_filter_date(:date_to)
      @date_filter_active = params[:date_from].present? || params[:date_to].present?
      @date_filter_error ||= @date_from && @date_to && @date_from > @date_to
      if @date_filter_error
        scope = scope.none
      elsif @date_filter_active
        scope = scope.where("questions.created_at >= ?", @date_from.beginning_of_day) if @date_from
        scope = scope.where("questions.created_at < ?", (@date_to + 1.day).beginning_of_day) if @date_to
      end
      @authors = User.where(id: scope.select(:author_id)).order(:name).pluck(:name)
      @topics = (scope.unscope(:order).pluck(:tags).flatten.uniq - Question::DIFFICULTIES).sort
      scope = scope.where("title ILIKE ?", "%#{@q}%") if @q.present?
      scope = scope.joins(:author).where(users: { name: @author }) if @author.present?
      scope = scope.where("? = ANY (tags)", @difficulty) if @difficulty.present?
      scope = scope.where("? = ANY (tags)", @topic) if @topic.present?
      scope
    end

    # Date fields submit ISO dates; malformed query strings become a visible empty result.
    def parse_filter_date(parameter)
      value = params[parameter].to_s
      Date.iso8601(value) if value.present?
    rescue ArgumentError
      @date_filter_error = true
      nil
    end
end
