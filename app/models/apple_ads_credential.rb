class AppleAdsCredential < ApplicationRecord
  belongs_to :organization

  include SanitizesCredentialErrors
  include Vaulted

  # The identifiers stay on Rails AR Encryption — they aren't signing material,
  # and the deterministic-encrypted ones must remain queryable for scoped
  # lookups.
  encrypts :client_id, deterministic: true
  encrypts :team_id, deterministic: true
  encrypts :key_id

  # private_key_pem (the actual signing material) is read AND written
  # exclusively through the envelope column (mysigner-32 cutover). The legacy
  # AR-encrypted `private_key_pem` column physically remains in the schema as
  # a rollback window; mysigner-33 drops it.
  vaults :private_key_pem, kind: "apple_ads"

  validates :client_id, presence: true, length: { maximum: 64 }
  validates :team_id, presence: true, length: { maximum: 32 }
  validates :key_id, presence: true, length: { maximum: 32 }
  validates :private_key_pem, presence: true
  validate :private_key_must_be_ec

  # Note: both commit callbacks must target DIFFERENT method names. Rails
  # dedups after_commit callbacks by filter symbol, so `after_destroy_commit
  # :foo` followed by `after_update_commit :foo` silently overrides the first.
  #
  # The `before_destroy` snapshot is required because an Organization
  # cascade-destroy (`dependent: :destroy`) tears down apple_apps inside the
  # same transaction; by the time `after_destroy_commit` fires, the
  # organization record is gone and `organization.apple_apps` returns [].
  # Snapshotting inside the destroy transaction — before apple_apps are
  # reaped — keeps the scaffold-key purge correct on both direct credential
  # destroys and org-cascade destroys. (organization.rb declares
  # apple_ads_credential BEFORE apple_apps, so this callback fires while
  # apple_apps are still live.)
  before_destroy :snapshot_scaffold_app_store_ids
  after_destroy_commit :purge_cached_tokens_on_destroy
  after_update_commit :purge_cached_tokens_on_sensitive_update, if: :saved_change_to_sensitive_fields?

  def last_successful?
    last_successful_at.present?
  end

  def mark_success!(time: Time.current)
    update_columns(last_successful_at: time, last_error: nil)
  end

  def mark_failure!(error_message, time: Time.current)
    update_columns(
      last_error: sanitize_error(error_message).to_s.truncate(200),
      last_successful_at: nil
    )
  end

  private

  # Invalidating a credential without purging the cached access_token would
  # leave up to ~55 minutes of usable access (and the client_assertion JWT
  # cache would outlive the credential by months). Purge both on destroy
  # AND on any sensitive-field update (rotating keys should invalidate
  # the cached tokens minted from the old key).
  def purge_cached_tokens_on_destroy
    purge_cached_tokens
  end

  def purge_cached_tokens_on_sensitive_update
    purge_cached_tokens
  end

  def snapshot_scaffold_app_store_ids
    @scaffold_app_store_ids = organization&.apple_apps&.pluck(:app_store_id) || []
  end

  def purge_cached_tokens
    Rails.cache.delete("aso/apple_ads/access_token/#{id}")
    Rails.cache.delete("aso/apple_ads/assertion/#{id}")
    # Scaffold keys are per (credential_id, app_store_id). Purge every app's
    # scaffold so a destroy-then-recreate (or key rotation) doesn't leave
    # stale PAUSED campaign IDs pointing at campaigns the new credential
    # has no authority over. On destroy, use the snapshot taken before the
    # org cascade reaped apple_apps; on update, query live (the org is
    # definitely still around).
    app_store_ids = @scaffold_app_store_ids || organization&.apple_apps&.pluck(:app_store_id) || []
    app_store_ids.each do |app_store_id|
      Rails.cache.delete("aso/apple_ads/scaffold/#{id}/#{app_store_id}")
    end
  end

  def saved_change_to_sensitive_fields?
    saved_change_to_client_id? ||
      saved_change_to_team_id? ||
      saved_change_to_key_id? ||
      saved_change_to_private_key_pem?
  end

  def private_key_must_be_ec
    return if private_key_pem.blank?
    key = OpenSSL::PKey.read(private_key_pem)
    errors.add(:private_key_pem, "must be an EC (ES256) key") unless key.is_a?(OpenSSL::PKey::EC)
  rescue OpenSSL::PKey::PKeyError, ArgumentError
    errors.add(:private_key_pem, "is not a valid PEM-encoded private key")
  end
end
