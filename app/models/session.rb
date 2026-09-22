# Persistent login session for a user.
class Session < ApplicationRecord
  belongs_to :user
end
