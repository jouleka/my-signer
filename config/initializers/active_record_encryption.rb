# Strict Active Record Encryption configuration.
# Sources: 1) ENV vars; 2) Rails credentials.
# If missing, raise loudly to avoid silent misconfiguration.

# Skip during Docker build asset precompilation (SECRET_KEY_BASE_DUMMY is set)
if ENV["SECRET_KEY_BASE_DUMMY"].present?
  Rails.application.config.active_record.encryption.primary_key = "dummy_primary_key_for_asset_precompile"
  Rails.application.config.active_record.encryption.deterministic_key = "dummy_deterministic_key_for_assets"
  Rails.application.config.active_record.encryption.key_derivation_salt = "dummy_salt_for_asset_precompile"
  return
end

cfg = {
  primary_key: ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"],
  deterministic_key: ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"],
  key_derivation_salt: ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]
}

if cfg.values.any?(&:blank?)
  cred = Rails.application.credentials.active_record_encryption || {}
  cfg[:primary_key] ||= cred[:primary_key]
  cfg[:deterministic_key] ||= cred[:deterministic_key]
  cfg[:key_derivation_salt] ||= cred[:key_derivation_salt]
end

missing = cfg.select { |_, v| v.blank? }.keys
if missing.any?
  if Rails.env.production?
    raise "Missing Active Record encryption config: #{missing.join(", ")}"
  else
    # Provide deterministic non-production defaults (dev/test/ci) to avoid boot failures
    cfg[:primary_key] ||= "nonprod_primary_key_1234567890abcdef12345678"
    cfg[:deterministic_key] ||= "nonprod_deterministic_key_abcdef12345678"
    cfg[:key_derivation_salt] ||= "nonprod_kdf_salt_1234567890abcdef"
  end
end

Rails.application.config.active_record.encryption.primary_key = cfg[:primary_key]
Rails.application.config.active_record.encryption.deterministic_key = cfg[:deterministic_key]
Rails.application.config.active_record.encryption.key_derivation_salt = cfg[:key_derivation_salt]

# Optional previous-keyring support for in-flight rotation.
#
# When the operator sets ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY_PREVIOUS and/or
# ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY_PREVIOUS, Rails AR encryption can
# DECRYPT rows still wrapped under the old key while NEW writes go under the
# current primary/deterministic. The operator then runs:
#
#   * `bin/rails active_record_encryption:rotate_keyring`               (primary; mysigner-33)
#   * `bin/rails active_record_encryption:rotate_deterministic_keyring` (deterministic; follow-up to mysigner-33)
#
# to re-encrypt rows under the new keys. Once verified, the _PREVIOUS env vars
# can be removed permanently.
#
# Caveat for deterministic rotation: WHERE-clause lookups on a deterministic
# column (e.g. `GooglePlayCredential.find_by(developer_account_id: "X")`)
# only match rows wrapped under the CURRENT deterministic key. Until the
# rotate task finishes, lookups on old-key rows return nil. The KDF salt is
# NOT independently rotatable; both rotation procedures keep it stable.
previous_providers = []

previous_primary = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY_PREVIOUS"].presence
if previous_primary
  previous_providers << { key_provider: ActiveRecord::Encryption::DerivedSecretKeyProvider.new(previous_primary) }
end

previous_deterministic = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY_PREVIOUS"].presence
if previous_deterministic
  previous_providers << { key_provider: ActiveRecord::Encryption::DerivedSecretKeyProvider.new(previous_deterministic) }
end

if previous_providers.any?
  Rails.application.config.active_record.encryption.previous = previous_providers
end
