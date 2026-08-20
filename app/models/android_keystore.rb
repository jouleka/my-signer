class AndroidKeystore < ApplicationRecord
  belongs_to :organization
  belongs_to :android_app, optional: true

  include Vaulted

  # keystore_file, keystore_password and key_password are read AND written
  # exclusively through their envelope columns (mysigner-32 cutover). The
  # legacy AR-encrypted columns physically remain in the schema as a rollback
  # window; mysigner-33 drops them. Each attribute gets its own `kind` so the
  # KMS EncryptionContext distinguishes them — preventing an attacker who can
  # swap envelopes within a row from moving a password envelope into the
  # keystore_file slot or vice versa.
  vaults :keystore_file,     kind: "android_keystore"
  vaults :keystore_password, kind: "android_keystore_password"
  vaults :key_password,      kind: "android_key_password"

  before_validation :squish_fields
  before_save :validate_credentials_with_keytool!, if: :should_validate_with_keytool?
  before_save :ensure_exclusive_active_keystore, if: -> { active? && (will_save_change_to_active? || will_save_change_to_android_app_id?) }

  validates :name, presence: true, length: { maximum: 120 }, uniqueness: { scope: :organization_id, message: "already exists for this organization" }
  validates :keystore_file, presence: true
  validates :keystore_password, presence: true
  validates :active, inclusion: { in: [ true, false ] }

  # Prevent uploading the exact same keystore file (identified by fingerprint) twice in the same organization
  validates :fingerprint_sha256, uniqueness: { scope: :organization_id, message: "has already been uploaded. You cannot upload the same keystore twice." }, allow_nil: true

  scope :active, -> { where(active: true) }
  scope :for_app, ->(android_app_id) { where(android_app_id: android_app_id) }
  # Get keystores available for an app (app-specific + org-wide)
  scope :available_for_app, ->(android_app_id) { where(android_app_id: [ android_app_id, nil ]) }
  scope :expiring_within, lambda { |days|
    return none if days.to_i <= 0
    where.not(expires_at: nil).where("expires_at <= ?", days.to_i.days.from_now.end_of_day)
  }

  # Activate this keystore. If assigned to an app, ensure it's the only active one for that app.
  def activate_exclusively!
    update!(active: true)
  end

  # Convenience: return keystore size for basic integrity sanity checks
  def keystore_size_bytes
    data = keystore_file
    data ? data.bytesize : 0
  end

  def expired?
    expires_at.present? && expires_at < Date.current
  end

  def expiring_soon?(days = 30)
    return false if expires_at.blank?
    cutoff = days.to_i.days.from_now.to_date
    expires_at <= cutoff
  end

  def days_until_expiry
    return nil if expires_at.blank?
    (expires_at - Date.current).to_i
  end

  def validate_credentials_with_keytool!
    result = Android::KeystoreValidator.new(
      keystore_data: keystore_file,
      keystore_password: keystore_password,
      key_alias: key_alias,
      key_password: key_password
    ).validate!

    self.expires_at = result.valid_until&.to_date if result.valid_until.present?
    self.fingerprint_sha256 = result.fingerprints[:sha256] if result.fingerprints && result.fingerprints[:sha256]
    true
  rescue Android::KeystoreValidator::ValidationError => e
    # Only add the specific message, not the stack trace
    errors.add(:base, e.message)
    throw :abort
  end

  private

  def squish_fields
    self.name = name.to_s.strip
    self.key_alias = key_alias.to_s.strip
    self.keystore_password = keystore_password.to_s.strip
    self.key_password = key_password.to_s.strip
  end

  def ensure_exclusive_active_keystore
    # Deactivate other keystores in the same scope (app-specific or org-wide)
    self.class.where(organization_id: organization_id, android_app_id: android_app_id)
              .where.not(id: id)
              .where(active: true)
              .update_all(active: false)
  end

  def should_validate_with_keytool?
    new_record? || keystore_file_changed? || keystore_password_changed? || key_password_changed? || key_alias_changed?
  end
end
