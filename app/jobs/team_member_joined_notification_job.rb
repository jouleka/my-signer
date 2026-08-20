class TeamMemberJoinedNotificationJob < ApplicationJob
  queue_as :default

  def perform(organization_id:, new_member_id:)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    new_member = User.find_by(id: new_member_id)
    return unless new_member

    new_member_name = new_member.name || new_member.email

    organization.memberships.includes(:user).find_each do |membership|
      next if membership.user_id == new_member_id

      user = membership.user
      next unless user.notify_team_activity?

      # Org-level notifications carry NULL resource_type/id, so the unique
      # indexes never trip and the old `rescue RecordNotUnique` was dead. Use
      # an atomic, stable cache claim keyed on (org, recipient, new member) so a
      # double-delivered job doesn't duplicate the notification.
      key = "team_member_joined:#{organization.id}:#{user.id}:#{new_member_id}"
      next unless claim_dedup!(key: key)

      begin
        Notification.create!(
          user: user,
          organization: organization,
          notification_type: "team_member_joined",
          title: "New Team Member",
          message: "#{new_member_name} has joined #{organization.name}."
        )
      rescue StandardError
        release_dedup!(key: key)
        raise
      end

      # Email admins only
      if membership.admin?
        NotificationMailer.team_member_joined(
          user: user,
          new_member: new_member,
          organization: organization
        ).deliver_later
      end
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
