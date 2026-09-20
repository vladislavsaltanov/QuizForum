class Question < ApplicationRecord
  ANSWER_TYPES = %w[text code single_choice multiple_choice].freeze
  DIFFICULTIES = %w[легкое среднее сложное].freeze

  belongs_to :author, class_name: "User"
  has_many :attempts, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :reports, dependent: :destroy

  validates :title, :deadline, presence: true
  validates :answer_type, inclusion: { in: ANSWER_TYPES }

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
end
