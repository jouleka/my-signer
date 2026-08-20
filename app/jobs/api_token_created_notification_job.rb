class ApiTokenCreatedNotificationJob < ApplicationJob
  queue_as :default

  def perform(organization_id:, creator_id:, token_name:)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    creator = User.find_by(id: creator_id)
    return unless creator

    creator_name = creator.name || creator.email

    # Notify admin members except the creator
    organization.memberships.admin.includes(:user).find_each do |membership|
      next if membership.user_id == creator_id

      user = membership.user
      next unless user.notify_team_activity?

      # Org-level notifications carry NULL resource_type/id, so the unique
      # indexes on `notifications` never trip and the old `rescue
      # RecordNotUnique` was dead. Use an atomic cache claim (Solid Cache in
      # production = DB-backed, shared across workers) keyed on the event
      # identity so a double-delivered job doesn't duplicate the notification.
      next unless claim_dedup!(key: "api_token_created:#{organization.id}:#{user.id}:#{token_name}")

      begin
        Notification.create!(
          user: user,
          organization: organization,
          notification_type: "api_token_created",
          title: "New API Token",
          message: "#{creator_name} created API token '#{token_name}' in #{organization.name}."
        )
      rescue StandardError
        release_dedup!(key: "api_token_created:#{organization.id}:#{user.id}:#{token_name}")
        raise
      end

      NotificationMailer.api_token_created(
        user: user,
        creator: creator,
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
