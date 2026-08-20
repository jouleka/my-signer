class ResourceRevokedNotificationJob < ApplicationJob
  queue_as :default

  def perform(resource_type:, resource_id:, organization_id:)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    resource = resource_type.constantize.find_by(id: resource_id)
    return unless resource

    resource_type_label = resource_type.titleize
    resource_name = resource.respond_to?(:name) ? resource.name : "Resource"

    organization.memberships.includes(:user).find_each do |membership|
      user = membership.user
      next unless user.notify_revocations?

      # One per resource per user, ever
      already_notified = Notification.exists?(
        user: user,
        resource_type: resource_type,
        resource_id: resource_id,
        notification_type: "resource_revoked"
      )
      next if already_notified

      Notification.create!(
        user: user,
        organization: organization,
        resource_type: resource_type,
        resource_id: resource_id,
        notification_type: "resource_revoked",
        title: "#{resource_type_label} Revoked",
        message: "#{resource_type_label} '#{resource_name}' has been revoked or marked as invalid."
      )

      NotificationMailer.resource_revoked(
        user: user,
        resource: resource,
        resource_type_label: resource_type_label
      ).deliver_later
    rescue ActiveRecord::RecordNotUnique
      # Dedup race condition
    end
  end
end
