class Comment < ApplicationRecord
  STATUSES = %w[pending approved].freeze

  belongs_to :question
  belongs_to :user

  validates :body, presence: true
  validates :status, inclusion: { in: STATUSES }

  broadcasts_to :question, inserts_by: :append, target: "comments", if: :visible_live?

  def approved?
    status == "approved"
  end

  private
    # ponytail: realtime only for comments everyone may see; the rest render on reload.
    def visible_live?
      approved? || question.closed?
    end
end
