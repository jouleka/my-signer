class MembershipChangedNotificationJob < ApplicationJob
  queue_as :default

  EVENTS = %w[role_changed removed].freeze

  def perform(organization_id:, actor_id:, target_user_id:, event:, metadata: {})
    return unless EVENTS.include?(event)

    organization = Organization.find_by(id: organization_id)
    return unless organization

    actor = User.find_by(id: actor_id)
    target_user = User.find_by(id: target_user_id)
    return unless actor && target_user

    recipient_ids = organization.memberships.admin.pluck(:user_id)
    recipient_ids << target_user.id if event == "role_changed"
    recipient_ids = recipient_ids.uniq - [ actor.id ]

    recipient_ids.each do |uid|
      user = User.find_by(id: uid)
      next unless user
      next unless user.notify_member_activity?

      # Org-level notifications carry NULL resource_type/id, so the unique
      # indexes never trip and the old `rescue RecordNotUnique` was dead. Use an
      # atomic, stable cache claim keyed on the event so a double-delivered job
      # doesn't duplicate the notification.
      case event
      when "role_changed"
        old_role = metadata[:old_role] || metadata["old_role"]
        new_role = metadata[:new_role] || metadata["new_role"]

        key = "member_role_changed:#{organization.id}:#{user.id}:#{target_user.id}:#{old_role}:#{new_role}"
        next unless claim_dedup!(key: key)

        begin
          Notification.create!(
            user: user,
            organization: organization,
            notification_type: "member_role_changed",
            title: "Member role changed",
            message: "#{actor.name.presence || actor.email} changed #{target_user.name.presence || target_user.email}'s role from #{old_role} to #{new_role} in #{organization.name}."
          )
        rescue StandardError
          release_dedup!(key: key)
          raise
        end

        NotificationMailer.member_role_changed(
          user: user,
          actor: actor,
          target_user: target_user,
          organization: organization,
          old_role: old_role,
          new_role: new_role
        ).deliver_later
      when "removed"
        key = "member_removed:#{organization.id}:#{user.id}:#{target_user.id}"
        next unless claim_dedup!(key: key)

        begin
          Notification.create!(
            user: user,
            organization: organization,
            notification_type: "member_removed",
            title: "Member removed",
            message: "#{actor.name.presence || actor.email} removed #{target_user.name.presence || target_user.email} from #{organization.name}."
          )
        rescue StandardError
          release_dedup!(key: key)
          raise
        end

        NotificationMailer.member_removed(
          user: user,
          actor: actor,
          target_user: target_user,
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
