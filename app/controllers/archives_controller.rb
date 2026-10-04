# Read-only list of questions the landing feed has already dropped.
class ArchivesController < ApplicationController
  include Paginates
  include FiltersQuestions

  # Closed longer than the archive grace period, newest closure first; same filters as the feed.
  def show
    @questions = paginate(filter_questions(Question.archived)).includes(:author, :attempts)
  end
end
