class AppStoreConnectCredential < ApplicationRecord
  belongs_to :organization

  include SanitizesCredentialErrors
  include Vaulted

  encrypts :key_id, deterministic: true
  encrypts :issuer_id

  # private_key is read AND written exclusively through the envelope column
  # (mysigner-32 cutover). The legacy AR-encrypted `private_key` column
  # physically remains in the schema as a rollback window; mysigner-33 drops it.
  vaults :private_key, kind: "asc"

  # Normalizations
  before_validation :squish_fields

  # Validations
  validates :name, presence: true, length: { maximum: 120 }, uniqueness: { scope: :organization_id }
  validates :key_id, presence: true, length: { in: 8..64 }
  validates :issuer_id, presence: true, length: { in: 20..64 }
  validates :private_key, presence: true
  validates :active, inclusion: { in: [ true, false ] }

  # Scopes
  scope :active, -> { where(active: true) }

  # Cache invalidation — drop any cached JWT when any component of the
  # JWT header or signature changes: private_key signs the token, but key_id
  # goes in the header (kid claim) and issuer_id is the iss claim. Rotating
  # any of them without invalidating the cache would leave a stale JWT in
  # place for up to 13 minutes and trigger 401s from Apple. Distinct method
  # names avoid the Rails after_commit dedupe-by-symbol footgun.
  after_update_commit  :purge_cached_jwt_on_update, if: :jwt_signing_material_changed?
  after_destroy_commit :purge_cached_jwt_on_destroy

  # Helpers
  def mark_sync_success!(time: Time.current)
    update_columns(last_synced_at: time, last_sync_status: "ok", last_sync_error: nil)
  end

  def mark_sync_failure!(error, time: Time.current)
    update_columns(last_synced_at: time, last_sync_status: "error", last_sync_error: sanitize_error(error).to_s.truncate(2000))
  end

  private

  def squish_fields
    self.name = name.to_s.strip
    self.key_id = key_id.to_s.strip
    self.issuer_id = issuer_id.to_s.strip
    self.private_key = private_key.to_s.strip
  end

  def jwt_signing_material_changed?
    saved_change_to_private_key? || saved_change_to_key_id? || saved_change_to_issuer_id?
  end

  def purge_cached_jwt_on_update
    purge_cached_jwt
  end

  def purge_cached_jwt_on_destroy
    purge_cached_jwt
  end

  def purge_cached_jwt
    Rails.cache.delete("asc_jwt:#{id}")
  end

  public

  # Atomically activate this credential and deactivate others for the same organization
  def activate_exclusively!
    transaction do
      self.class.where(organization_id: organization_id).update_all(active: false)
      reload
      update!(active: true)
    end
  end
end
