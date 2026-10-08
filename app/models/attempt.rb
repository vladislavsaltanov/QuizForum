# One user's answer to a question; immutable after create.
class Attempt < ApplicationRecord
  VERDICTS = %w[pending correct partial incorrect].freeze
  # Jury suggestion labels from sidecar grade_v2.
  JURY_LABELS = %w[positive partial false].freeze
  # Verdicts the author may set by hand (pending is transitional, never manual).
  MANUAL_VERDICTS = %w[correct partial incorrect].freeze
  # Code-answer languages; values double as select labels. Single-sourced from
  # the runner so ungradeable languages are rejected here, never stuck pending.
  LANGUAGES = CodeRunnerClient::SUPPORTED_LANGUAGES

  belongs_to :question
  belongs_to :user

  validates :user_id, uniqueness: { scope: :question_id }
  validates :verdict, inclusion: { in: VERDICTS }
  validates :language, inclusion: { in: LANGUAGES }, allow_nil: true
  validates :body, length: { maximum: 8000 }, allow_nil: true
  validate :answer_present
  validate :selected_indices_valid, if: -> { question&.choice? }

  # Points per user for correct verdicts on revealed questions, highest first.
  # ponytail: Ruby sum over correct attempts, not SQL; fine at forum scale.
  def self.revealed_points(difficulty: nil, topic: nil)
    scope = joins(:question).where(verdict: "correct").where("questions.deadline <= ?", Time.current)
    scope = scope.where("? = ANY (questions.tags)", difficulty) if difficulty.present?
    scope = scope.where("? = ANY (questions.tags)", topic) if topic.present?
    points = Hash.new(0)
    scope.includes(:question).find_each { points[it.user_id] += it.question.difficulty_weight }
    users = User.where(id: points.keys).index_by(&:id)
    points.filter_map { |uid, n| users[uid] && [ users[uid], n ] }.sort_by { |u, n| [ -n, u.name ] }
  end

  before_create :grade_choice!

  # Correct verdict on a revealed question: the only state the leaderboard counts.
  def revealed_correct?
    verdict == "correct" && question.closed?
  end

  # Streams the live verdict chips and stats; call only on closed questions.
  def broadcast_verdict_change
    stats = question.attempts.group(:verdict).count
    broadcast_replace_to(question, target: "question-stats", partial: "questions/stats", locals: { stats: })
    broadcast_replace_to(question, target: ActionView::RecordIdentifier.dom_id(self, :verdict),
      partial: "attempts/chip", locals: { attempt: self, prefix: :verdict })
    broadcast_replace_to(question, target: ActionView::RecordIdentifier.dom_id(self, :my_verdict),
      partial: "attempts/chip", locals: { attempt: self, prefix: :my_verdict })
    # Summary only here (closed): the stream is shared, pre-deadline grouping must not leak.
    broadcast_replace_to(question, target: "question-summary",
      partial: "questions/summary", locals: { attempts: question.attempts.includes(:user).order(:created_at) })
  end


  private
    # Choice answers need selected options, text answers need a body.
    def answer_present
      if question.choice?
        errors.add(:selected, :blank) if selected.blank?
      else
        errors.add(:body, :blank) if body.blank?
      end
    end

    # Forged indexes would render nil and crash the page for every viewer.
    def selected_indices_valid
      size = question.options.size
      Array(selected).each do |s|
        unless s.to_s.match?(/\A\d+\z/) && s.to_i.between?(0, size - 1)
          errors.add(:selected, :inclusion)
          break
        end
      end
    end

    # Choice verdicts derived at create; text/code stay pending for the Jury.
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
