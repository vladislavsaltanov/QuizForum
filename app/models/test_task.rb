# One inline task (задание) inside a Test; never called Question.
class TestTask < ApplicationRecord
  ANSWER_TYPES = %w[text single_choice multiple_choice].freeze

  belongs_to :test, inverse_of: :test_tasks
  has_many :test_attempts, dependent: :destroy

  validates :body, presence: true
  validates :answer_type, inclusion: { in: ANSWER_TYPES }
  validates :points, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  before_validation :compact_options, if: :choice?
  validate :options_complete, if: :choice?

  # True for single- or multiple-choice tasks.
  def choice?
    single_choice? || multiple_choice?
  end

  def single_choice?
    answer_type == "single_choice"
  end

  def multiple_choice?
    answer_type == "multiple_choice"
  end

  # Option indexes flagged correct, as strings matching TestAttempt#selected.
  def correct_indices
    options.each_index.select { options[it]["correct"] }.map(&:to_s)
  end

  # Points this verdict earns: full for correct, half rounded down for partial.
  def score_for(verdict)
    case verdict.to_s
    when "correct" then points
    when "partial" then points / 2
    else 0
    end
  end

  private
    # Blank option rows from the form never reach grading.
    def compact_options
      self.options = Array(options).filter_map do |o|
        o = o.to_h
        text = o["text"].to_s.strip
        next if text.empty?
        { "text" => text, "correct" => !!o["correct"] }
      end
    end

    # Choice options must be 2-8 with a valid correct flag.
    def options_complete
      errors.add(:options, :blank) if options.size < 2
      errors.add(:options, "must have at most 8 items") if options.size > 8
      errors.add(:options, :inclusion) if single_choice? && options.count { it["correct"] } != 1
      errors.add(:options, :inclusion) if multiple_choice? && options.none? { it["correct"] }
    end
end
