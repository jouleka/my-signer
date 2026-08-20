class ApiTokenRevokedNotificationJob < ApplicationJob
  queue_as :default

  def perform(organization_id:, revoker_id:, token_name:)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    revoker = User.find_by(id: revoker_id)
    return unless revoker

    revoker_name = revoker.name.presence || revoker.email

    # Notify admin members except the revoker
    organization.memberships.admin.includes(:user).find_each do |membership|
      next if membership.user_id == revoker_id

      user = membership.user
      next unless user.notify_api_token_activity?

      # Org-level notifications carry NULL resource_type/id, so the unique
      # indexes never trip and the old `rescue RecordNotUnique` was dead. Use
      # an atomic, stable cache claim so a double-delivered job doesn't
      # duplicate the notification.
      key = "api_token_revoked:#{organization.id}:#{user.id}:#{token_name}"
      next unless claim_dedup!(key: key)

      begin
        Notification.create!(
          user: user,
          organization: organization,
          notification_type: "api_token_revoked",
          title: "API Token Revoked",
          message: "#{revoker_name} revoked API token '#{token_name}' in #{organization.name}."
        )
      rescue StandardError
        release_dedup!(key: key)
        raise
      end

      NotificationMailer.api_token_revoked(
        user: user,
        revoker: revoker,
        token_name: token_name,
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
