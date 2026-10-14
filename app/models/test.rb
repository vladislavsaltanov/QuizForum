# Moodle-style test: a combination of Questions that live only inside it,
# answered all at once with one submit. Open or password-protected.
# Lifecycle: draft (invisible to strangers) -> published. Questions are added
# one by one from the creation screen through the regular question form bound
# to the test; the list shows bare titles, no inline forms.
class Test < ApplicationRecord
  # NULL digest = open test; has_secure_password would require a password on
  # create, so validations stay off and blank simply means no gate.
  has_secure_password validations: false

  belongs_to :author, class_name: "User"
  has_many :questions, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :test
  has_many :comments, dependent: :destroy, validate: false

  validates :title, :deadline, presence: true
  validates :title, length: { maximum: 200 }
  validates :body, length: { maximum: 20_000 }, allow_nil: true
  validates :max_points, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  scope :published, -> { where(published: true) }

  # Home feed: strangers see open published tests without a password gate,
  # nearest deadline first (direct link is the only way to password tests).
  scope :home_feed, -> do
    published.where(password_digest: nil).where(deadline: Time.current..).order(deadline: :asc)
  end

  # Tests the user answered: attempts point at questions, questions know
  # their test. Two subqueries, no row loading and no N+1.
  scope :taken_by, ->(user) do
    where(id: Question.where(id: Attempt.where(user_id: user.id).select(:question_id)).select(:test_id))
  end

  # Still being assembled: invisible to everyone but the author.
  def draft?
    !published?
  end

  # Deadline still in the future.
  def open?
    deadline.future?
  end

  # Closed tests reveal scores and verdicts.
  def closed?
    !open?
  end

  # Author or admin only; same bar as questions.
  def editable_by?(user)
    author == user || user&.admin?
  end

  # Full read access; comment premoderation uses it too.
  def privileged?(user)
    editable_by?(user)
  end

  # True when the author set a password.
  def protected?
    password_digest.present?
  end

  # Author passes free; everyone else needs the session flag from #authenticate.
  def unlocked?(user, session)
    !protected? || author == user || session[unlock_key] == true
  end

  def unlock_key
    "test_#{id}_ok"
  end

  # Ceiling for the scoreboard: explicit override, else the sum of question points.
  def max_score
    max_points || questions.sum(&:points)
  end

  # True once the user answered every question in one go; attempts only
  # ever appear together, so one row is enough to tell.
  def answered_by?(user)
    Attempt.where(question_id: questions.map(&:id), user_id: user.id).exists?
  end

  # Sum over the user's attempts: correct = full points, partial = half
  # rounded down (integer division), anything else 0. Two queries, no N+1.
  def total_score(user)
    attempts = Attempt.where(question_id: questions.map(&:id), user_id: user.id).index_by(&:question_id)
    questions.sum { it.score_for(attempts[it.id]&.verdict) }
  end
end
