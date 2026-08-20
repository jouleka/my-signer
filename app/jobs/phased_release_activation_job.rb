# Background job to activate phased release after app approval
# This job polls Apple's API to check if the version is ready for phased release activation
class PhasedReleaseActivationJob < ApplicationJob
  queue_as :apple_polling

  # Maximum time to keep retrying (96 hours = 4 days)
  MAX_RETRY_HOURS = 96

  # Retry intervals: 15m, 30m, 1h, 2h, 4h, then 4h thereafter
  RETRY_INTERVALS = [ 15.minutes, 30.minutes, 1.hour, 2.hours, 4.hours ].freeze

  retry_on StandardError, wait: :polynomially_longer, attempts: 50

  def perform(version_id, started_at: nil)
    started_at ||= Time.current
    version = AppStoreVersion.find_by(id: version_id)

    # Version deleted or no longer pending
    return unless version&.phased_release_pending?

    # Check if we've exceeded the maximum retry time
    if Time.current - started_at > MAX_RETRY_HOURS.hours
      Rails.logger.warn("[PhasedReleaseActivationJob] Giving up on version #{version_id} after #{MAX_RETRY_HOURS} hours")
      version.update!(phased_release_pending: false)
      return
    end

    credential = version.organization.app_store_connect_credentials.find_by(active: true)
    unless credential
      Rails.logger.warn("[PhasedReleaseActivationJob] No active credential for version #{version_id}")
      version.update!(phased_release_pending: false)
      return
    end

    apple_client = AppStoreConnect::Client.new(credential: credential)
    versions_service = AppStoreConnect::Versions.new(apple_client)

    eligibility = versions_service.phased_release_eligibility(version_id: version.version_id)

    case eligibility
    when :can_activate
      # App is approved - activate phased release
      versions_service.create_phased_release(version_id: version.version_id, state: "ACTIVE")
      version.update!(phased_release_pending: false)
      Rails.logger.info("[PhasedReleaseActivationJob] Activated phased release for version #{version_id}")
    when :already_active
      # Already activated (maybe manually) - just clear the flag
      version.update!(phased_release_pending: false)
      Rails.logger.info("[PhasedReleaseActivationJob] Phased release already active for version #{version_id}")
    when :pending_review
      # Still in review - schedule retry
      retry_after = calculate_retry_interval(started_at)
      Rails.logger.info("[PhasedReleaseActivationJob] Version #{version_id} still in review, retrying in #{retry_after / 60} minutes")
      self.class.set(wait: retry_after).perform_later(version_id, started_at: started_at)
    when :removed_from_sale
      # App removed - give up
      Rails.logger.warn("[PhasedReleaseActivationJob] Version #{version_id} removed from sale, giving up")
      version.update!(phased_release_pending: false)
    else
      # Invalid state - give up
      Rails.logger.warn("[PhasedReleaseActivationJob] Version #{version_id} in invalid state: #{eligibility}")
      version.update!(phased_release_pending: false)
    end
  rescue ActiveRecord::RecordNotFound
    # Version was deleted - nothing to do
    Rails.logger.info("[PhasedReleaseActivationJob] Version #{version_id} not found, skipping")
  end

  private

  def calculate_retry_interval(started_at)
    elapsed_hours = (Time.current - started_at) / 1.hour

    case elapsed_hours
    when 0...1 then RETRY_INTERVALS[0]  # First hour: every 15 min
    when 1...2 then RETRY_INTERVALS[1]  # Second hour: every 30 min
    when 2...4 then RETRY_INTERVALS[2]  # Hours 2-4: every 1 hour
    when 4...8 then RETRY_INTERVALS[3]  # Hours 4-8: every 2 hours
    else RETRY_INTERVALS[4]             # After 8 hours: every 4 hours
    end
  end
end
