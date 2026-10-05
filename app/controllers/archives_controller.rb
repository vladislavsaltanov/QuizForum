# Read-only list of questions the landing feed has already dropped.
class ArchivesController < ApplicationController
  include Paginates
  include FiltersQuestions

  # Closed longer than the archive grace period, newest closure first; same filters as the feed.
  # AI packs stay hidden unless the switch picks them; the switch itself hides with the kill switch.
  # ai=1 → only AI, ai=all → everything, anything else (default) → humans only.
  def show
    base = Question.archived
    @ai_filter = AiQuestions.enabled? && params[:ai].in?(%w[1 all]) ? params[:ai] : "0"
    base = base.ai if @ai_filter == "1"
    base = base.human if @ai_filter == "0"
    @questions = paginate(filter_questions(base)).includes(:author, :attempts)
  end
end
