# Short clarifying note on a question; hidden until approved or revealed.
class Comment < ApplicationRecord
  STATUSES = %w[pending approved].freeze

  belongs_to :question
  belongs_to :user

  validates :body, presence: true
  validates :status, inclusion: { in: STATUSES }

  broadcasts_to :question, inserts_by: :append, target: "comments", if: :visible_live?

  # Approved comments are visible to everyone.
  def approved?
    status == "approved"
  end

  private
    # Broadcast only comments everyone may already see.
    def visible_live?
      approved? || question.closed?
    end
end
