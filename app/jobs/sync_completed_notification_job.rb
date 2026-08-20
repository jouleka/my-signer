class SyncCompletedNotificationJob < ApplicationJob
  queue_as :default

  DEDUP_WINDOW = 6.hours

  def perform(organization_id:, changes_summary:)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    organization.memberships.includes(:user).find_each do |membership|
      user = membership.user
      next unless user.notify_sync_changes?

      # 6-hour dedup per org. The Notification.exists? check below is the
      # primary dedup, but org-level notifications carry NULL resource_type/id
      # so neither unique index on `notifications` ever trips — the old
      # `rescue RecordNotUnique` was dead code and concurrent syncs could both
      # pass this exists? check and insert duplicates. We acquire an atomic
      # cache-based claim (Solid Cache in production = DB-backed, shared across
      # workers) as the real race backstop.
      already_notified = Notification.exists?(
        user: user,
        organization: organization,
        notification_type: "sync_completed",
        created_at: DEDUP_WINDOW.ago..
      )
      next if already_notified

      next unless claim_dedup!(organization: organization, user: user)

      begin
        Notification.create!(
          user: user,
          organization: organization,
          notification_type: "sync_completed",
          title: "Sync Completed",
          message: "Sync for #{organization.name} found changes: #{changes_summary.join(', ')}"
        )
      rescue StandardError
        # Creation failed — release the claim so a retry can re-notify.
        release_dedup!(organization: organization, user: user)
        raise
      end

      # Only email when 3+ resources changed
      if changes_summary.size >= 3
        NotificationMailer.sync_completed(
          user: user,
          organization: organization,
          changes_summary: changes_summary
        ).deliver_later
      end
    end
  end

  private

  # Atomically claim the dedup slot for (org, user) within the dedup window.
  # Returns true only for the first caller; concurrent callers get false and
  # skip. `unless_exist: true` is an atomic set-if-absent on the cache store.
  def claim_dedup!(organization:, user:)
    Rails.cache.write(
      dedup_key(organization: organization, user: user),
      true,
      unless_exist: true,
      expires_in: DEDUP_WINDOW
    )
  end

  def release_dedup!(organization:, user:)
    Rails.cache.delete(dedup_key(organization: organization, user: user))
  end

  def dedup_key(organization:, user:)
    "sync_completed_notification:#{organization.id}:#{user.id}"
  end
end
