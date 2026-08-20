class SsoJitProvisionedNotificationJob < ApplicationJob
  queue_as :default

  def perform(organization_id:, provisioned_user_id:)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    provisioned = User.find_by(id: provisioned_user_id)
    return unless provisioned

    organization.memberships.admin.includes(:user).find_each do |membership|
      user = membership.user
      next if user.id == provisioned.id
      next unless user.notify_sso_activity?

      # Org-level notifications carry NULL resource_type/id, so the unique
      # indexes never trip and the old `rescue RecordNotUnique` was dead. Use
      # an atomic, stable cache claim so a double-delivered job doesn't
      # duplicate the notification.
      key = "sso_jit_provisioned:#{organization.id}:#{user.id}:#{provisioned.id}"
      next unless claim_dedup!(key: key)

      begin
        Notification.create!(
          user: user,
          organization: organization,
          notification_type: "sso_jit_provisioned",
          title: "New SSO user",
          message: "#{provisioned.email} was auto-provisioned in #{organization.name} via SSO."
        )
      rescue StandardError
        release_dedup!(key: key)
        raise
      end

      NotificationMailer.sso_jit_user_provisioned(
        user: user,
        provisioned_user: provisioned,
        organization: organization
      ).deliver_later
    end
  end

  private

  DEDUP_TTL = 24.hours

  def claim_dedup!(key:)
    Rails.cache.write(key, true, unless_exist: true, expires_in: DEDUP_TTL)
  end

  def release_dedup!(key:)
    Rails.cache.delete(key)
  end
end
