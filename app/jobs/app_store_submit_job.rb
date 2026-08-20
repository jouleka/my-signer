class AppStoreSubmitJob < ApplicationJob
  include SanitizesErrorMessage

  queue_as :default

  # Submits an App Store version for review via Apple's reviewSubmissions API.
  #
  # The job is the single source of truth for "is a submission in flight":
  #   submission_status = "submitting" → job running (set by controller before enqueue)
  #   submission_status = "submitted"  → Apple accepted; state also updated to WAITING_FOR_REVIEW
  #   submission_status = "failed"     → Apple rejected or an error occurred; submission_error set
  #
  # Release type is updated on the Apple version BEFORE submission (MANUAL and
  # SCHEDULED only — AFTER_APPROVAL is Apple's default and needs no PATCH).
  #
  # @param organization_id [Integer]
  # @param app_store_version_id [Integer] Local AppStoreVersion ID
  # @param release_type [String] AFTER_APPROVAL | MANUAL | SCHEDULED (default AFTER_APPROVAL)
  # @param earliest_release_date [String, nil] ISO 8601 timestamp, required when release_type=SCHEDULED
  def perform(organization_id:, app_store_version_id:, release_type: "AFTER_APPROVAL", earliest_release_date: nil)
    version = locate_version(organization_id, app_store_version_id)
    return unless version # record not found — nothing we can do

    organization = version.organization
    credential = organization.app_store_connect_credentials.find_by(active: true)
    unless credential
      record_failure(version, "No active App Store Connect credential. Add one in Settings.")
      return
    end

    client = AppStoreConnect::Client.new(credential: credential)
    versions_service = AppStoreConnect::Versions.new(client)

    begin
      # Update release_type on the Apple version first, if the user changed it.
      # Apple stores releaseType on the version itself, not on the submission.
      if %w[MANUAL SCHEDULED].include?(release_type)
        versions_service.update_release_settings(
          version_id: version.version_id,
          release_type: release_type,
          earliest_release_date: earliest_release_date
        )
      end

      # Submit for review. The service internally reuses any existing open draft
      # for (app, platform) to honor Apple's one-open-submission-per-platform rule.
      result = versions_service.submit_for_review(
        app_id: version.apple_app.app_store_id,
        version_id: version.version_id,
        platform: version.platform.presence || "IOS"
      )

      Rails.logger.info(
        "[AppStoreSubmitJob] version=#{version.id} submission_id=#{result['submission_id']} reused=#{result['reused']}"
      )

      # Update local state. The after_update callback on AppStoreVersion fires
      # ReleaseEvents::Notifier.notify_ios_state_change automatically when
      # app_store_state transitions to WAITING_FOR_REVIEW.
      version.update!(
        app_store_state: "WAITING_FOR_REVIEW",
        submission_status: "submitted",
        submission_error: nil
      )

      # Clear stale validation errors — if Apple accepted the submission, any
      # previously-stored errors are no longer relevant.
      refresh_validation_errors(version, versions_service)
    rescue StandardError => e
      Rails.logger.error("[AppStoreSubmitJob] failed: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
      record_failure(version, format_error_message(e))
      refresh_validation_errors(version, versions_service)
    end
  end

  private

  # Returns the version or nil. Handles the two NotFound cases explicitly so
  # that a deleted Organization or deleted Version doesn't leave the record
  # stuck in "submitting" — if we can locate the version at all, we reset its
  # status before returning nil.
  def locate_version(organization_id, app_store_version_id)
    organization = Organization.find_by(id: organization_id)
    unless organization
      # Can't reach the version without its org, but we can still try to
      # reset it directly so the UI doesn't stay stuck.
      stray = AppStoreVersion.find_by(id: app_store_version_id)
      if stray&.submission_status == "submitting"
        stray.update_columns(submission_status: "failed", submission_error: "Organization no longer exists.")
      end
      Rails.logger.warn("[AppStoreSubmitJob] Organization #{organization_id} not found")
      return nil
    end

    version = organization.app_store_versions.find_by(id: app_store_version_id)
    unless version
      Rails.logger.warn("[AppStoreSubmitJob] AppStoreVersion #{app_store_version_id} not found in org #{organization_id}")
      return nil
    end

    version
  end

  def record_failure(version, message)
    version.update_columns(
      submission_status: "failed",
      submission_error: sanitize_error_message(message)
    )
  end

  # Best-effort refresh of Apple's validation errors for the version. Failures
  # are logged and swallowed — this runs after the main submission work is
  # done, so its success or failure should not affect the caller's flow.
  def refresh_validation_errors(version, versions_service)
    errors = versions_service.validation_errors(version_id: version.version_id)
    version.update_issues_from_apple_errors!(errors)
  rescue StandardError => e
    Rails.logger.warn("[AppStoreSubmitJob] validation_errors refresh failed: #{e.message}")
  end

  def format_error_message(error)
    msg = error.message.to_s

    # Detect Apple's "not in valid state" error — almost always means first-time
    # metadata is missing from App Store Connect. Rewrite into something actionable.
    if msg.include?("not in valid state") || msg.include?("cannot be reviewed")
      return "This version can't be submitted yet. For first-time submissions, " \
             "configure screenshots, description, keywords, age rating, and " \
             "privacy policy in App Store Connect, then submit again."
    end

    # Detect age-rating deadline (Jan 31, 2026) errors. Apple returns a
    # specific error code when the updated questionnaire is missing.
    if msg.downcase.include?("age rating")
      return "Age rating questionnaire must be completed in App Store Connect " \
             "(required since Jan 2026). Update it and try again."
    end

    sanitize_error_message(msg)
  end
end
