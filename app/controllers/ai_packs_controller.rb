# Daily AI rubric page: the current pack grouped by difficulty.
class AiPacksController < ApplicationController
  # Shows the latest pack still on the feed; nothing to show redirects home.
  def show
    @ai_pack = Question.latest_ai_pack
    redirect_to root_path if @ai_pack.empty?
  end
end
