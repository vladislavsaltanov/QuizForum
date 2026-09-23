# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # Moderated texts never hit disk: hard block covers DB, this covers logs.
  :title, :body, :name, :reference_answer, :explanation, :tags_string,
  # Jury payloads carry answer texts and suggestions; same treatment.
  :jury_label, :jury_score, :jury_needs_review, :jury_reasons
]
