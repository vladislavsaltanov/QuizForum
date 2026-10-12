# Short clarifying note; lives on a Question or on a Test (exactly one).
# Hidden until approved or revealed by the deadline.
class Comment < ApplicationRecord
  STATUSES = %w[pending approved].freeze

  belongs_to :question, optional: true
  belongs_to :test, optional: true
  belongs_to :user

  validates :body, presence: true
  validates :body, length: { maximum: 2000 }
  validates :status, inclusion: { in: STATUSES }
  validate :exactly_one_owner

  # Approved comments are visible to everyone.
  def approved?
    status == "approved"
  end

  # The Question or Test this comment hangs on.
  def owner
    question || test
  end

  # Shows approved and own comments. Shows all comments to privileged users and after the deadline.
  def self.visible_for(question, user)
    scope = where(question: question)
    return scope if question.privileged?(user) || question.closed?
    scope.where(status: "approved").or(scope.where(user: user))
  end

  # Same discipline for a test: the author premoderates, the Deadline reveals.
  def self.visible_for_test(test, user)
    scope = where(test: test)
    return scope if test.privileged?(user) || test.closed?
    scope.where(status: "approved").or(scope.where(user: user))
  end

  # Broadcast bubbles only when everyone may already see them (question branch).
  def visible_live?
    approved? || question&.closed?
  end

  private
    # A comment belongs to a Question or to a Test, never both, never neither.
    def exactly_one_owner
      return if question_id.present? ^ test_id.present?
      errors.add(:base, "must belong to a question or a test")
    end
end
