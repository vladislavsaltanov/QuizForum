# Published task; reference material stays hidden until the deadline.
class Question < ApplicationRecord
  ANSWER_TYPES = %w[text code single_choice multiple_choice].freeze
  DIFFICULTIES = %w[легкое среднее сложное].freeze
  # How long a closed question stays on the landing feed before the archive takes it.
  ARCHIVE_GRACE = 7.days
  # Deadline horizon that makes a question urgent enough to top the feed.
  CLOSING_SOON = 24.hours

  belongs_to :author, class_name: "User"
  has_many :attempts, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :reports, dependent: :destroy
  has_many :question_trustees, dependent: :destroy
  has_many :trustees, through: :question_trustees, source: :user

  validates :title, :deadline, presence: true
  validates :body, presence: true
  validates :title, length: { maximum: 200 }
  validates :body, :reference_answer, :explanation, length: { maximum: 20_000 }, allow_nil: true
  validates :reference_answer, presence: true, unless: :choice?
  validates :answer_type, inclusion: { in: ANSWER_TYPES }
  before_validation :compact_options, if: :choice?
  before_validation :compact_code_languages, if: :code?
  validate :options_complete, if: :choice?
  validate :code_languages_valid

  # Deadline still in the future.
  def open?
    deadline.future?
  end

  # Closed questions reveal everything.
  def closed?
    !open?
  end

  # Open with at most a day left: the cohort that needs answering first.
  def closing_soon?
    open? && deadline <= CLOSING_SOON.from_now
  end

  # Landing feed: open questions plus a tail of closed ones, urgent first.
  # AI packs get a short tail (AiQuestions::ARCHIVE_GRACE) instead of the human week;
  # with the kill switch off AI rows never reach the feed at all.
  # now() is used straight in SQL because Rails pins the session time zone to UTC,
  # which is where deadline lives; passing a Ruby timestamp would drift by the zone offset.
  def self.feed
    human_feed.or(ai_feed).order(Arel.sql(feed_order))
  end

  # Everything the feed has dropped, newest closure first.
  def self.archived
    human_archived.or(ai_archived).order(deadline: :desc)
  end

  scope :ai, -> { where(ai_generated: true) }
  scope :human, -> { where(ai_generated: false) }

  # Feed/archived halves; AI halves go empty when the kill switch is off.
  def self.human_feed
    human.where("questions.deadline >= now() - make_interval(secs => ?)", ARCHIVE_GRACE.to_i)
  end

  def self.ai_feed
    return none unless AiQuestions.enabled?
    ai.where("questions.deadline >= now() - make_interval(secs => ?)", AiQuestions::ARCHIVE_GRACE.to_i)
  end

  def self.human_archived
    human.where(deadline: ..ARCHIVE_GRACE.ago)
  end

  def self.ai_archived
    return none unless AiQuestions.enabled?
    ai.where("questions.deadline < now() - make_interval(secs => ?)", AiQuestions::ARCHIVE_GRACE.to_i)
  end

  # Latest AI batch still on the feed (today's open pack, or yesterday's
  # during its 2-hour closed tail before the archive takes it).
  def self.latest_ai_pack
    return [] unless AiQuestions.enabled?
    rows = ai_feed.includes(:author, :attempts).order(ai_batch: :desc).to_a
    return [] if rows.empty?
    rows.take_while { it.ai_batch == rows.first.ai_batch }
  end

  def self.feed_order
    # Columns stay qualified because the feed is often joined to users for author filters.
    soon = "questions.deadline > now() AND questions.deadline <= now() + make_interval(secs => #{CLOSING_SOON.to_i})"
    <<~SQL.squish
      CASE
        WHEN #{soon} THEN 0
        WHEN questions.deadline > now() THEN 1
        ELSE 2
      END,
      CASE WHEN #{soon} THEN questions.deadline END ASC NULLS LAST,
      questions.created_at DESC
    SQL
  end
  private_class_method :feed_order

  # True for single- or multiple-choice questions.
  def choice?
    single_choice? || multiple_choice?
  end

  # Exactly one correct option.
  def single_choice?
    answer_type == "single_choice"
  end

  # One or more correct options.
  def multiple_choice?
    answer_type == "multiple_choice"
  end

  # Code answer graded by differential fuzzing (see design doc 2026-10-07).
  def code?
    answer_type == "code"
  end

  # Languages the diff-fuzzing checker may grade (spec section 1).
  CODE_LANGUAGES = %w[python javascript typescript ruby c++ c# java go].freeze

  # Points for a correct verdict: 1/2/3 by difficulty, 1 when untagged.
  DIFFICULTY_WEIGHTS = { "легкое" => 1, "среднее" => 2, "сложное" => 3 }.freeze

  # Weight of this question in points.
  def difficulty_weight
    DIFFICULTY_WEIGHTS.fetch((tags & DIFFICULTIES).first, 1)
  end

  # Option indexes flagged correct, as strings matching Attempt#selected.
  def correct_indices
    options.each_index.select { options[it]["correct"] }.map(&:to_s)
  end

  # Author, trustee, or admin: full read access.
  def privileged?(user)
    author == user || user&.admin? || trustee?(user)
  end

  # Per-question observer grant, regardless of deadline.
  def trustee?(user)
    user.present? && trustees.exists?(user.id)
  end

  # Author or admin only; trustees keep view access but never edit.
  def editable_by?(user)
    author == user || user&.admin?
  end

  # Author or admin only; trustees never manage grants.
  def managed_by?(user)
    editable_by?(user)
  end

  # Replace the trustee set from comma-separated emails; returns [ok, alert, problems].
  # problems is one "email — reason" line per address that did not become a trustee.
  def sync_trustees_by_emails(raw)
    emails = raw.to_s.split(",").map { it.strip.downcase }.reject(&:empty?).uniq
    users = User.where(email: emails).index_by(&:email)
    kept = users.values.map(&:id)
    rejected = []
    # Grant before revoke, in one transaction: a rejected email (author, race)
    # must never leave the question with fewer observers than it started with.
    transaction do
      users.each_value do |u|
        rejected << u unless question_trustees.find_or_initialize_by(user: u).save
      end
      question_trustees.where.not(user_id: kept).destroy_all if rejected.empty?
    end
    problems = trustee_problems(emails, users.keys, rejected)
    return [ true, nil, [] ] if problems.empty?
    [ false, "Добавлено наблюдателей: #{emails.size - problems.size} из #{emails.size}.", problems ]
  end

  private
    # Why each address failed: unknown mailbox, or a grant the model refused.
    def trustee_problems(emails, found, rejected)
      (emails - found).map { "#{it} — нет пользователя с таким email" } +
        rejected.map { "#{it.email} — #{it.id == author_id ? "это вы, автор вопроса" : "не удалось сохранить"}" }
    end

    # Blank option rows from the dynamic form never reach grading.
    def compact_options
      self.options = Array(options).filter_map do |o|
        o = o.to_h
        text = o["text"].to_s.strip
        next if text.empty?
        { "text" => text, "correct" => !!o["correct"] }
      end
    end

    # The unchecked-everything hidden field arrives as ["" blank]; "any" is [].
    def compact_code_languages
      self.code_languages = Array(code_languages).map(&:to_s).map(&:strip).reject(&:empty?)
    end

    # Language allowlist + reference language apply to code questions only;
    # stray languages on other types are rejected so they cannot leak into grading.
    def code_languages_valid
      if code?
        Array(code_languages).each do |lang|
          errors.add(:code_languages, :inclusion) unless CODE_LANGUAGES.include?(lang)
        end
        if reference_language.present?
          errors.add(:reference_language, :inclusion) unless CODE_LANGUAGES.include?(reference_language)
          if code_languages.present? && !code_languages.include?(reference_language)
            errors.add(:reference_language, :inclusion)
          end
        end
      else
        errors.add(:code_languages, :present) if code_languages.present?
        errors.add(:reference_language, :present) if reference_language.present?
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
