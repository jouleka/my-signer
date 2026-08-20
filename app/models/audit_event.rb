class AuditEvent < ApplicationRecord
  # Canonical list of all auditable actions. Adding a new action requires
  # appending here; stale actions should NOT be removed (legacy records may
  # reference them). The inclusion validation rejects typos at creation.
  ACTIONS = %w[
    member_invited
    member_added
    member_role_changed
    member_removed
    invitation_cancelled
    invitation_accepted
    api_token_created
    api_token_revoked
    asc_credential_added
    asc_credential_removed
    asc_credential_activated
    asc_credential_validation_failed
    google_play_credential_added
    google_play_credential_removed
    google_play_credential_activated
    android_keystore_added
    android_keystore_removed
    android_keystore_activated
    apple_ads_credential_added
    apple_ads_credential_removed
    tracked_keyword_added
    tracked_keyword_removed
    organization_created
    organization_updated
    organization_deleted
    plan_upgraded
    plan_downgraded
    schedule_cleared
    trial_expired
    billing_portal_accessed
    sign_in_failed
    password_changed
    email_changed
    store_listing_pushed
    play_store_pushed
    release_submitted
    sso_login
    sso_login_failed
    sso_configuration_created
    sso_configuration_updated
    sso_configuration_removed
    sync_all_triggered
    store_listing_keywords_updated
    keyword_idea_saved
    keyword_idea_removed
    credential_read_android_keystore_file
    credential_read_android_keystore_secrets
    credential_read_google_play_token
    credential_decrypted
    asc_credential_used
    apple_ads_credential_used
    asc_build_upload_created
    asc_build_upload_finalized
    asc_build_upload_status_checked
    account_soft_deleted
    account_restored
    deletion_token_regenerated
    owner_soft_deleted_co_member_notified
    trial_ended_by_user
    byok_registered
    byok_cleared
    byok_verify_failed
    byok_kms_key_revoked_detected
    credential_destroyed_on_logout
  ].freeze

  # Organization is optional so an `organization_deleted` event can be
  # recorded before destroy AND survive the FK nullify cascade. Regular
  # in-life events always set organization_id; a NULL organization_id means
  # the org has since been deleted.
  belongs_to :organization, optional: true
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :resource, polymorphic: true, optional: true

  validates :action, presence: true, inclusion: { in: ACTIONS }
  validates :created_at, presence: true
  # organization_id must be present at write-time. The DB FK switches it to
  # NULL later via ON DELETE NULLIFY if the org is destroyed; that transition
  # is fine, but a caller writing an event without an org is a bug.
  validates :organization_id, presence: true, on: :create

  # Immutability: audit events are append-only. Updates and destroys go through
  # these guards; retention cleanup bypasses them via delete_all (SQL-level).
  before_update { raise ActiveRecord::ReadOnlyRecord, "AuditEvent records are immutable" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "AuditEvent records cannot be destroyed individually" }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_actor, ->(actor_id) { where(actor_id: actor_id) }
  scope :for_action, ->(action) { where(action: action) }
  scope :in_date_range, ->(from, to) { where(created_at: from.beginning_of_day..to.end_of_day) }

  # Retention-only bulk deletion. Bypasses the before_destroy guard because
  # delete_all issues a raw DELETE without loading records.
  def self.delete_before(cutoff)
    where("created_at < ?", cutoff).in_batches(of: 1000).delete_all
  end

  def human_action
    action.humanize
  end

  def actor_display
    actor&.name.presence || actor&.email || "System"
  end
end
