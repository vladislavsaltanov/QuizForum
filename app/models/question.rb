class Question < ApplicationRecord
  ANSWER_TYPES = %w[text code single_choice multiple_choice].freeze
  DIFFICULTIES = %w[легкое среднее сложное].freeze

  belongs_to :author, class_name: "User"
  has_many :attempts, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :reports, dependent: :destroy
  has_many :question_trustees, dependent: :destroy
  has_many :trustees, through: :question_trustees, source: :user

  validates :title, :deadline, presence: true
  validates :body, presence: true
  validates :reference_answer, presence: true, unless: :choice?
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
    options.each_index.select { options[it]["correct"] }.map(&:to_s)
  end

  # ponytail: single gate for author-or-trustee-or-admin; controllers and views reuse it
  def privileged?(user)
    author == user || user&.admin? || trustee?(user)
  end

  def trustee?(user)
    user.present? && trustees.exists?(user.id)
  end

  # ponytail: grant management is author-or-admin only; trustees never manage
  def managed_by?(user)
    author == user || user&.admin?
  end

  # ponytail: comma-separated emails are the whole desired set; [ok, alert_or_nil]
  def sync_trustees_by_emails(raw)
    emails = raw.to_s.split(",").map { it.strip.downcase }.reject(&:empty?).uniq
    users = User.where(email: emails).index_by(&:email)
    missing = emails - users.keys
    question_trustees.where.not(user_id: users.values.map(&:id)).destroy_all
    invalid = users.values.filter_map do |u|
      grant = question_trustees.find_or_initialize_by(user: u)
      grant.save ? nil : grant.errors.full_messages.to_sentence
    end
    problems = missing.map { "Пользователь не найден: #{it}" } + invalid
    problems.empty? ? [ true, nil ] : [ false, problems.to_sentence ]
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
      errors.add(:options, :inclusion) if single_choice? && options.count { it["correct"] } != 1
      errors.add(:options, :inclusion) if multiple_choice? && options.none? { it["correct"] }
    end
end
