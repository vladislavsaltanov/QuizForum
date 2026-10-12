# One user's answer to one TestTask; immutable after create.
class TestAttempt < ApplicationRecord
  VERDICTS = %w[pending correct partial incorrect].freeze

  belongs_to :test_task
  belongs_to :user

  validates :user_id, uniqueness: { scope: :test_task_id }
  validates :verdict, inclusion: { in: VERDICTS }
  validates :body, length: { maximum: 8000 }, allow_nil: true
  validate :answer_present
  validate :selected_indices_valid, if: -> { test_task&.choice? }

  before_create :grade_choice!

  private
    # Choice answers need selected options, text answers need a body.
    def answer_present
      if test_task.choice?
        errors.add(:selected, :blank) if selected.blank?
      else
        errors.add(:body, :blank) if body.blank?
      end
    end

    # Forged indexes would render nil and crash the page for every viewer.
    def selected_indices_valid
      size = test_task.options.size
      Array(selected).each do |s|
        unless s.to_s.match?(/\A\d+\z/) && s.to_i.between?(0, size - 1)
          errors.add(:selected, :inclusion)
          break
        end
      end
    end

    # Choice verdicts derived at create; text stays pending (no Jury in MVP).
    def grade_choice!
      return unless test_task.choice?
      picked = Array(selected).map(&:to_s)
      correct = test_task.correct_indices
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
