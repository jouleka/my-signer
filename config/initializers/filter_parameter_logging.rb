# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  :authorization, :api_key, :private_key, :access_token, :bearer, :client_secret,
  :client_assertion,
  # Rails partial-matches on the outer parameter key, not inside JSON values.
  # Without these, POST /google_play_credentials logs the full service-account
  # JSON (including the embedded private_key string) because the outer key
  # `service_account_json` doesn't contain any substring in the list above.
  :service_account_json, :service_account,
  :keystore_password, :key_password, :keystore_file_base64,
  :source_file_checksums
]
