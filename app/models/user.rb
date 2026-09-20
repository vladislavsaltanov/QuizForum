class User < ApplicationRecord
  has_secure_password
  attr_accessor :current_password
  has_many :sessions, dependent: :destroy
  has_many :authored_questions, class_name: "Question", foreign_key: :author_id, dependent: :destroy
  has_many :attempts, dependent: :destroy
  has_many :comments, dependent: :destroy

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true

  def self.find_or_create_by_omniauth(auth)
    email = auth.info.email.to_s.strip.downcase
    find_by(provider: auth.provider, uid: auth.uid) ||
      find_by(email: email)&.tap { |user| user.update!(provider: auth.provider, uid: auth.uid) } ||
      create!(name: auth.info.name, email: email, provider: auth.provider, uid: auth.uid,
              password: SecureRandom.hex(32))
  end
end
