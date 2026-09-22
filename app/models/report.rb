# User flag on a question; one per user per question.
class Report < ApplicationRecord
  belongs_to :question
  belongs_to :user

  validates :user_id, uniqueness: { scope: :question_id }
end
