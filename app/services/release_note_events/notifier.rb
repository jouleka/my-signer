module ReleaseNoteEvents
  class Notifier
    # Fired when a developer submits a release note for review.
    # Notifies all admins (and the owner) so they know there is something to review.
    def self.notify_submitted_for_review(release_note, submitter:)
      return unless release_note
      organization = release_note.organization
      return unless organization
      return unless organization.supports_review_workflow?

      app = release_note.listable
      app_label = app_label_for(app)
      version = release_note.version_string.presence || "unversioned"
      title = "Release Notes Awaiting Review"
      message = "#{submitter&.email || 'A developer'} submitted release notes for #{app_label} v#{version}."

      # Reviewers = admins + owner (the people who CAN approve)
      recipient_ids = organization.memberships.where(role: [ :admin ]).pluck(:user_id)
      recipient_ids << organization.owner_id if organization.owner_id
      recipient_ids = recipient_ids.compact.uniq
      # Don't notify the submitter about their own action
      recipient_ids.delete(submitter&.id) if submitter

      recipient_ids.each do |user_id|
        user = User.find_by(id: user_id)
        next unless user&.notify_release_activity?

        create_notification(
          user_id: user_id,
          organization: organization,
          title: title,
          message: message,
          resource: release_note,
          notification_type: "release_note:submitted_for_review"
        )
      end
    rescue StandardError => e
      Rails.logger.error("ReleaseNoteEvents::Notifier#notify_submitted_for_review failed: #{e.class} - #{e.message}")
    end

    # Fired when an admin approves a release note.
    # Notifies the original author so they know they can apply it.
    def self.notify_approved(release_note, reviewer:)
      return unless release_note
      organization = release_note.organization
      return unless organization
      return unless organization.supports_review_workflow?

      author_id = release_note.created_by_id
      return unless author_id
      return if reviewer && author_id == reviewer.id  # don't notify yourself

      author = User.find_by(id: author_id)
      return unless author&.notify_release_activity?

      app = release_note.listable
      app_label = app_label_for(app)
      version = release_note.version_string.presence || "unversioned"
      title = "Release Notes Approved"
      message = "Your release notes for #{app_label} v#{version} were approved#{reviewer ? " by #{reviewer.email}" : ""}. You can now apply them to the store."

      create_notification(
        user_id: author_id,
        organization: organization,
        title: title,
        message: message,
        resource: release_note,
        notification_type: "release_note:approved"
      )
    rescue StandardError => e
      Rails.logger.error("ReleaseNoteEvents::Notifier#notify_approved failed: #{e.class} - #{e.message}")
    end

    # Fired when an admin requests changes on a release note.
    # Notifies the original author with the comment.
    def self.notify_changes_requested(release_note, reviewer:, comment:)
      return unless release_note
      organization = release_note.organization
      return unless organization
      return unless organization.supports_review_workflow?

      author_id = release_note.created_by_id
      return unless author_id
      return if reviewer && author_id == reviewer.id

      author = User.find_by(id: author_id)
      return unless author&.notify_release_activity?

      app = release_note.listable
      app_label = app_label_for(app)
      version = release_note.version_string.presence || "unversioned"
      title = "Changes Requested on Release Notes"
      truncated_comment = comment.to_s.strip.truncate(140)
      message = "#{reviewer&.email || 'A reviewer'} requested changes on #{app_label} v#{version}: #{truncated_comment}"

      create_notification(
        user_id: author_id,
        organization: organization,
        title: title,
        message: message,
        resource: release_note,
        notification_type: "release_note:changes_requested"
      )
    rescue StandardError => e
      Rails.logger.error("ReleaseNoteEvents::Notifier#notify_changes_requested failed: #{e.class} - #{e.message}")
    end

    def self.app_label_for(app)
      return "(unknown app)" unless app
      app.respond_to?(:name) && app.name.present? ? app.name :
        app.respond_to?(:bundle_id) && app.bundle_id.present? ? app.bundle_id :
          app.respond_to?(:package_name) && app.package_name.present? ? app.package_name :
            "(unknown app)"
    end

    def self.create_notification(user_id:, organization:, title:, message:, resource:, notification_type:)
      Notification.create!(
        user_id: user_id,
        organization_id: organization.id,
        notification_type: notification_type,
        title: title,
        message: message,
        resource: resource
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      Rails.logger.warn("ReleaseNoteEvents::Notifier skipped notification: #{e.message}")
    end
  end
end
