# Ranking by difficulty-weighted points for revealed correct verdicts, optional tag filters.
class LeaderboardsController < ApplicationController
  TOP_N = 20

  # Builds the ranked list plus the current user's position (even outside top N).
  def show
    @difficulty = params[:difficulty].to_s
    @topic = params[:topic].to_s
    @topics = (Question.pluck(:tags).flatten.uniq - Question::DIFFICULTIES).sort
    @ranking = Attempt.revealed_points(difficulty: @difficulty.presence, topic: @topic.presence)
    @top = @ranking.first(TOP_N)
    me = @ranking.index { |u, _| u.id == Current.user.id }
    @my_rank = me && me + 1
    @my_score = me ? @ranking[me][1] : 0
    @my_in_top = !me.nil? && me < TOP_N
  end
end
