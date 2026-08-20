class AppStoreVersion < ApplicationRecord
  # Apple app_store_state values where the version is eligible to be submitted
  # (or re-submitted) to App Review. These match the states where `submit_for_review`
  # against Apple's reviewSubmissions API is expected to succeed.
  SUBMITTABLE_STATES = %w[
    PREPARE_FOR_SUBMISSION
    READY_FOR_REVIEW
    DEVELOPER_REJECTED
    REJECTED
    METADATA_REJECTED
    INVALID_BINARY
    WAITING_FOR_EXPORT_COMPLIANCE
  ].freeze

  # submission_status values used by AppStoreSubmitJob + sync_status polling.
  # nil = no submission in flight ("idle" in the JSON polling response).
  SUBMISSION_STATUSES = %w[submitting submitted failed].freeze

  belongs_to :organization
  belongs_to :apple_app
  belongs_to :apple_build, optional: true

  validates :version_id, presence: true, uniqueness: true
  validates :version_string, presence: true

  scope :editable, -> { where(app_store_state: [ "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "WAITING_FOR_REVIEW", "INVALID_BINARY" ]) }

  after_update :notify_state_change, if: :saved_change_to_app_store_state?

  # True when the version's app_store_state allows a new submission to Apple.
  def submittable?
    SUBMITTABLE_STATES.include?(app_store_state.to_s)
  end

  # True while AppStoreSubmitJob is running against Apple.
  def submitting?
    submission_status == "submitting"
  end

  # Marks the version as currently submitting. Used by ReleasesController
  # before enqueueing AppStoreSubmitJob so the sync_status polling endpoint
  # can report the transient state immediately.
  def mark_submitting!
    update_columns(submission_status: "submitting", submission_error: nil)
  end

  # Atomically transitions to "submitting" only if no submission is already
  # in flight. Returns true if the transition happened, false if a submission
  # was already running (caller should abort). Used by the controller's
  # submit_to_store action to guard against double-submit races.
  #
  # Uses PostgreSQL's IS DISTINCT FROM so NULL values (never-submitted versions)
  # are treated as eligible — a plain `where.not(submission_status: "submitting")`
  # would exclude NULL rows because SQL treats `NULL != 'x'` as NULL, not TRUE.
  def claim_submission!
    rows = self.class
      .where(id: id)
      .where("submission_status IS DISTINCT FROM ?", "submitting")
      .update_all(submission_status: "submitting", submission_error: nil, updated_at: Time.current)
    reload if rows == 1
    rows == 1
  end

  # Normalizes an array of Apple validation error strings into the `issues`
  # JSONB shape used by the checklist and UI panels, and writes them.
  # Each stored issue has the shape {"code" => String, "detail" => String, "raw" => Hash}.
  def update_issues_from_apple_errors!(errors)
    normalized = Array(errors).map { |msg| { "code" => "UNKNOWN", "detail" => msg.to_s, "raw" => {} } }
    update_columns(issues: normalized, issues_synced_at: Time.current)
  end

  private

  def notify_state_change
    ReleaseEvents::Notifier.notify_ios_state_change(self)
  rescue StandardError => e
    Rails.logger.error("AppStoreVersion#notify_state_change failed: #{e.class} - #{e.message}")
  end
end
