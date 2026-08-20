class SyncFailedNotificationJob < ApplicationJob
  queue_as :default

  DEDUP_WINDOW = 24.hours

  def perform(credential_type:, credential_id:, organization_id:, error_message:)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    admin_members = organization.memberships.admin.includes(:user)

    admin_members.each do |membership|
      user = membership.user
      next unless user.notify_sync_failures?

      # 24-hour dedup per credential per user
      already_notified = Notification.exists?(
        user: user,
        resource_type: credential_type,
        resource_id: credential_id,
        notification_type: "sync_failed",
        created_at: DEDUP_WINDOW.ago..
      )
      next if already_notified

      notification = Notification.create!(
        user: user,
        organization: organization,
        resource_type: credential_type,
        resource_id: credential_id,
        notification_type: "sync_failed",
        title: "Sync Failed",
        message: "#{credential_type.titleize} sync failed for #{organization.name}: #{error_message.truncate(200)}"
      )

      NotificationMailer.sync_failed(
        user: user,
        credential_type: credential_type.titleize,
        organization: organization,
        error_message: error_message
      ).deliver_later
    rescue ActiveRecord::RecordNotUnique
      # Dedup race condition
    end
  end
end
