class GooglePlayCredential < ApplicationRecord
  belongs_to :organization

  include SanitizesCredentialErrors
  include Vaulted

  # `developer_account_id` stays AR-encrypted (deterministic) — it must remain
  # queryable for the unique-by-org constraint and is not signing material.
  encrypts :developer_account_id, deterministic: true

  # service_account_json is read AND written exclusively through the envelope
  # column (mysigner-32 cutover). The legacy AR-encrypted `service_account_json`
  # column physically remains in the schema as a rollback window; mysigner-33
  # drops it.
  vaults :service_account_json, kind: "google_play"

  # Normalizations
  before_validation :squish_fields

  # Validations
  validates :name, presence: true, length: { maximum: 120 }, uniqueness: { scope: :organization_id }
  validates :service_account_json, presence: true
  validates :active, inclusion: { in: [ true, false ] }
  validates :developer_account_id, uniqueness: { scope: :organization_id }, allow_nil: true, allow_blank: true

  validate :validate_service_account_json_structure

  # Cache invalidation — a stale cached access_token (up to ~55 minutes of
  # validity) would survive credential rotation or deletion. Purge on any
  # service_account_json change (key rotation) and on destroy.
  #
  # Note: the two commit callbacks must target DIFFERENT method names. Rails
  # dedups after_commit callbacks by filter symbol, so declaring both with
  # `:purge_cached_token` silently drops the earlier one. Same gotcha is
  # documented in AppleAdsCredential.
  after_update_commit  :purge_cached_token_on_update, if: :saved_change_to_service_account_json?
  after_destroy_commit :purge_cached_token_on_destroy

  # Scopes
  scope :active, -> { where(active: true) }

  # Helpers
  def mark_sync_success!(time: Time.current)
    update_columns(last_synced_at: time, last_sync_status: "ok", last_sync_error: nil)
  end

  def mark_sync_failure!(error, time: Time.current)
    update_columns(last_synced_at: time, last_sync_status: "error", last_sync_error: sanitize_error(error).to_s.truncate(2000))
  end

  # Atomically activate this credential and deactivate others for the same organization
  def activate_exclusively!
    transaction do
      self.class.where(organization_id: organization_id).update_all(active: false)
      # Use update_all to avoid validation/callback surprises and ensure DB state
      self.class.where(id: id).update_all(active: true)
      reload
    end
  end

  private

  def purge_cached_token_on_update
    purge_cached_token
  end

  def purge_cached_token_on_destroy
    purge_cached_token
  end

  def purge_cached_token
    Rails.cache.delete("gp_access_token:#{id}")
  end

  def squish_fields
    self.name = name.to_s.strip
    self.developer_account_id = developer_account_id.to_s.strip
    self.developer_account_id = nil if self.developer_account_id.blank?
    self.service_account_json = service_account_json.to_s.strip
  end

  def validate_service_account_json_structure
    raw = service_account_json.to_s
    return if raw.blank?
    begin
      data = JSON.parse(raw)
    rescue JSON::ParserError => e
      errors.add(:service_account_json, "must be valid JSON: #{sanitize_error(e.message)}")
      return
    end

    required_keys = %w[type project_id private_key client_email client_id]
    missing = required_keys - data.keys
    if missing.any?
      errors.add(:service_account_json, "missing required keys: #{missing.join(", ")}")
    end
  end

  public

  def client_email
    raw = service_account_json.to_s
    return nil if raw.blank?
    JSON.parse(raw)["client_email"] rescue nil
  end

  # Google Cloud project that owns this service account. Used to build the
  # "Enable API" link shown in the Play Reporting API banner.
  def project_id
    raw = service_account_json.to_s
    return nil if raw.blank?
    JSON.parse(raw)["project_id"] rescue nil
  end

  # True when the last sync attempt against
  # playdeveloperreporting.googleapis.com returned 403 SERVICE_DISABLED
  # for this credential's project. Cleared on the next successful call.
  def play_reporting_api_disabled?
    play_reporting_api_disabled_at.present?
  end

  # Deep link to the Google Cloud Console page where the Play Developer
  # Reporting API can be enabled for the project that owns this service
  # account. Returns nil if we can't determine the project_id (malformed
  # service_account_json, which validation should prevent).
  def play_reporting_api_enable_url
    pid = project_id
    return nil if pid.blank?
    "https://console.developers.google.com/apis/api/playdeveloperreporting.googleapis.com/overview?project=#{pid}"
  end

  def mark_play_reporting_api_disabled!
    update_columns(play_reporting_api_disabled_at: Time.current) if play_reporting_api_disabled_at.nil?
  end

  def mark_play_reporting_api_enabled!
    update_columns(play_reporting_api_disabled_at: nil) if play_reporting_api_disabled_at.present?
  end
end
