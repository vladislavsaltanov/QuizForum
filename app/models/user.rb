# Account: password or OAuth identity, authored and trusted questions.
class User < ApplicationRecord
  has_secure_password
  attr_accessor :current_password
  has_many :sessions, dependent: :destroy
  has_many :authored_questions, class_name: "Question", foreign_key: :author_id, dependent: :destroy
  has_many :attempts, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :question_trustees, dependent: :destroy
  has_many :trusted_questions, through: :question_trustees, source: :question

  normalizes :email, with: -> { it.strip.downcase }

  generates_token_for :email_confirmation, expires_in: 3.days do
    email
  end

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true
  validates :password, length: { minimum: 12 }, allow_nil: true
  validates :display_role, length: { maximum: 50 }, allow_nil: true

  # Email ownership verified.
  def confirmed?
    email_confirmed_at.present?
  end

  # Signed token bound to the current email.
  def email_confirmation_token
    generate_token_for(:email_confirmation)
  end

  # Token lifetime, mirrors the generates_token_for expiry.
  def email_confirmation_token_expires_in
    3.days
  end

  # Look up by confirmation token, raising when invalid.
  def self.find_by_email_confirmation_token!(token)
    find_by_token_for!(:email_confirmation, token)
  end

  # Link a Google identity to an existing account or create one, already confirmed.
  def self.find_or_create_by_omniauth(auth)
    email = auth.info.email.to_s.strip.downcase
    find_by(provider: auth.provider, uid: auth.uid) ||
      find_by(email: email)&.tap { it.update!(provider: auth.provider, uid: auth.uid, email_confirmed_at: Time.current) } ||
      create!(name: auth.info.name, email: email, provider: auth.provider, uid: auth.uid,
              password: SecureRandom.hex(32), email_confirmed_at: Time.current)
  end
end
