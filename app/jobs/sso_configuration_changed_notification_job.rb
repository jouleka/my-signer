class SsoConfigurationChangedNotificationJob < ApplicationJob
  queue_as :default

  EVENTS = %w[created updated removed].freeze

  def perform(organization_id:, actor_id:, event:)
    organization = Organization.find_by(id: organization_id)
    return unless organization
    return unless EVENTS.include?(event)

    actor = User.find_by(id: actor_id)
    return unless actor

    actor_name = actor.name.presence || actor.email

    organization.memberships.admin.includes(:user).find_each do |membership|
      next if membership.user_id == actor_id

      user = membership.user
      next unless user.notify_sso_activity?

      # Org-level notifications carry NULL resource_type/id, so the unique
      # indexes never trip and the old `rescue RecordNotUnique` was dead. Use
      # an atomic, stable cache claim keyed on the event so a double-delivered
      # job doesn't duplicate the notification.
      key = "sso_configuration_changed:#{organization.id}:#{user.id}:#{event}"
      next unless claim_dedup!(key: key)

      begin
        Notification.create!(
          user: user,
          organization: organization,
          notification_type: "sso_configuration_changed:#{event}",
          title: "SSO #{event}",
          message: "#{actor_name} #{event} the SSO configuration for #{organization.name}."
        )
      rescue StandardError
        release_dedup!(key: key)
        raise
      end

      NotificationMailer.sso_configuration_changed(
        user: user,
        actor: actor,
        organization: organization,
        event: event
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
