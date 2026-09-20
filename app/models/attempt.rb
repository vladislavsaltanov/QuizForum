class Attempt < ApplicationRecord
  VERDICTS = %w[pending correct partial incorrect].freeze
  # ponytail: bigtech-style list; values double as labels
  LANGUAGES = %w[bash c c# c++ elixir go haskell java javascript kotlin php python ruby rust scala sql swift typescript].freeze

  belongs_to :question
  belongs_to :user

  validates :user_id, uniqueness: { scope: :question_id }
  validates :verdict, inclusion: { in: VERDICTS }
  validate :answer_present

  before_create :grade_choice!

  private
    def answer_present
      if question.choice?
        errors.add(:selected, :blank) if selected.blank?
      else
        errors.add(:body, :blank) if body.blank?
      end
    end

    # ponytail: choice verdicts derived inline; text/code stay pending for the Jury.
    def grade_choice!
      return unless question.choice?
      picked = Array(selected).map(&:to_s)
      correct = question.correct_indices
      self.verdict =
        if picked.sort == correct.sort
          "correct"
        elsif (picked & correct).any?
          "partial"
        else
          "incorrect"
        end
    end
end
