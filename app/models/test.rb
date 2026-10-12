# Moodle-style test: N inline tasks (TestTask), open or password-protected.
class Test < ApplicationRecord
  # NULL digest = open test; has_secure_password would require a password on
  # create, so validations stay off and blank simply means no gate.
  has_secure_password validations: false

  belongs_to :author, class_name: "User"
  has_many :test_tasks, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :test

  validates :title, :deadline, presence: true
  validates :title, length: { maximum: 200 }
  validates :body, length: { maximum: 20_000 }, allow_nil: true
  validates :max_points, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  # Deadline still in the future.
  def open?
    deadline.future?
  end

  # Closed tests reveal scores and verdicts.
  def closed?
    !open?
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

  # Ceiling for the scoreboard: explicit override, else the sum of task points.
  def max_score
    max_points || test_tasks.sum(&:points)
  end

  # Sum over the user's attempts: correct = full points, partial = half
  # rounded down (integer division), anything else 0. Two queries, no N+1.
  def total_score(user)
    attempts = TestAttempt.where(test_task_id: test_tasks.map(&:id), user_id: user.id).index_by(&:test_task_id)
    test_tasks.sum { it.score_for(attempts[it.id]&.verdict) }
  end
end
