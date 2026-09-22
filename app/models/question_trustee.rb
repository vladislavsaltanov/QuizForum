class QuestionTrustee < ApplicationRecord
  belongs_to :question
  belongs_to :user

  validates :user_id, uniqueness: { scope: :question_id }
  validate :author_cannot_be_trustee

  private
    def author_cannot_be_trustee
      errors.add(:user, :invalid) if question && question.author_id == user_id
    end
end
