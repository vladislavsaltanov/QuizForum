# Short clarifying note on a question; hidden until approved or revealed.
class Comment < ApplicationRecord
  STATUSES = %w[pending approved].freeze

  belongs_to :question
  belongs_to :user

  validates :body, presence: true
  validates :body, length: { maximum: 2000 }
  validates :status, inclusion: { in: STATUSES }

  broadcasts_to :question, inserts_by: :append, target: "comments", if: :visible_live?

  # Approved comments are visible to everyone.
  def approved?
    status == "approved"
  end

  # Approved plus own comments; every status for the privileged viewer.
  def self.visible_for(question, user)
    scope = where(question: question)
    return scope if question.privileged?(user)
    scope.where(status: "approved").or(scope.where(user: user))
  end

  private
    # Broadcast only comments everyone may already see.
    def visible_live?
      approved? || question.closed?
    end
end
