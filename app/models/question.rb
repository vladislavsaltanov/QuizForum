class Question < ApplicationRecord
  ANSWER_TYPES = %w[text code single_choice multiple_choice].freeze
  DIFFICULTIES = %w[легкое среднее сложное].freeze

  belongs_to :author, class_name: "User"
  has_many :attempts, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :reports, dependent: :destroy

  validates :title, :deadline, presence: true
  validates :body, :reference_answer, presence: true
  validates :answer_type, inclusion: { in: ANSWER_TYPES }
  before_validation :compact_options, if: :choice?
  validate :options_complete, if: :choice?

  def open?
    deadline.future?
  end

  def closed?
    !open?
  end

  def choice?
    single_choice? || multiple_choice?
  end

  def single_choice?
    answer_type == "single_choice"
  end

  def multiple_choice?
    answer_type == "multiple_choice"
  end

  def correct_indices
    options.each_index.select { |i| options[i]["correct"] }.map(&:to_s)
  end

  private
    # ponytail: blank rows from the static form never reach grading
    def compact_options
      self.options = Array(options).filter_map do |o|
        o = o.to_h
        text = o["text"].to_s.strip
        next if text.empty?
        { "text" => text, "correct" => !!o["correct"] }
      end
    end

    def options_complete
      errors.add(:options, :blank) if options.size < 2
      errors.add(:options, "must have at most 6 items") if options.size > 6
      errors.add(:options, :inclusion) if single_choice? && options.count { |o| o["correct"] } != 1
      errors.add(:options, :inclusion) if multiple_choice? && options.none? { |o| o["correct"] }
    end
end
