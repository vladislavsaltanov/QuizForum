# Ranking by correct verdicts on revealed questions, optional tag filters.
class LeaderboardsController < ApplicationController
  TOP_N = 20

  # Builds the ranked list plus the current user's position (even outside top N).
  def show
    @difficulty = params[:difficulty].to_s
    @topic = params[:topic].to_s
    @topics = (Question.pluck(:tags).flatten.uniq - Question::DIFFICULTIES).sort
    scores = Attempt.joins(:question)
      .where(verdict: "correct")
      .where("questions.deadline <= ?", Time.current)
    scores = scores.where("? = ANY (questions.tags)", @difficulty) if @difficulty.present?
    scores = scores.where("? = ANY (questions.tags)", @topic) if @topic.present?
    counts = scores.group("attempts.user_id").count
    users = User.where(id: counts.keys).index_by(&:id)
    # GROUP BY count omits zero-score users, nothing further to exclude.
    @ranking = counts.filter_map { |uid, n| users[uid] && [ users[uid], n ] }
      .sort_by { |u, n| [ -n, u.name ] }
    @top = @ranking.first(TOP_N)
    me = @ranking.index { |u, _| u.id == Current.user.id }
    @my_rank = me && me + 1
    @my_score = me ? @ranking[me][1] : 0
    @my_in_top = !me.nil? && me < TOP_N
  end
end
