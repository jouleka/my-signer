module ReleaseEvents
  class Notifier
    # iOS app_store_state values that warrant an in-app notification.
    # Values are used to build the title/message for each event.
    IOS_SIGNIFICANT_STATES = {
      "READY_FOR_SALE" => { title: "Release Live on App Store", icon: "fa-rocket" },
      "REJECTED" => { title: "App Store Submission Rejected", icon: "fa-circle-xmark" },
      "METADATA_REJECTED" => { title: "App Store Metadata Rejected", icon: "fa-triangle-exclamation" },
      "DEVELOPER_REJECTED" => { title: "App Store Developer Rejected", icon: "fa-triangle-exclamation" },
      "IN_REVIEW" => { title: "App Store Review Started", icon: "fa-hourglass-half" },
      "WAITING_FOR_REVIEW" => { title: "Submitted for App Store Review", icon: "fa-paper-plane" },
      "INVALID_BINARY" => { title: "Invalid Binary on App Store", icon: "fa-circle-xmark" },
      "PENDING_DEVELOPER_RELEASE" => { title: "Ready for Release", icon: "fa-check" }
    }.freeze

    # Android PlayStoreRelease.status values that warrant an in-app notification.
    ANDROID_SIGNIFICANT_STATES = {
      "live" => { title: "Release Live on Google Play", icon: "fa-rocket" },
      "rejected" => { title: "Google Play Submission Rejected", icon: "fa-circle-xmark" },
      "submitted" => { title: "Submitted for Google Play Review", icon: "fa-paper-plane" }
    }.freeze

    def self.notify_ios_state_change(version)
      return unless version.is_a?(AppStoreVersion)
      return unless version.saved_change_to_app_store_state?

      old_state, new_state = version.saved_change_to_app_store_state
      return if old_state == new_state

      config = IOS_SIGNIFICANT_STATES[new_state]
      return unless config

      app = version.apple_app
      return unless app

      organization = app.organization || version.organization
      return unless organization

      app_label = app.name.presence || app.bundle_id
      message = "#{app_label} (v#{version.version_string}): #{config[:title]}"

      recipient_ids = organization.memberships.where(role: [ :admin, :developer ]).pluck(:user_id)
      recipient_ids << organization.owner_id if organization.owner_id
      recipient_ids = recipient_ids.compact.uniq

      recipient_ids.each do |user_id|
        user = User.find_by(id: user_id)
        next unless user&.notify_release_activity?

        create_notification(
          user_id: user_id,
          organization: organization,
          title: config[:title],
          message: message,
          resource: version,
          notification_type: "ios_state_change:#{new_state}"
        )
      end
    rescue StandardError => e
      Rails.logger.error("ReleaseEvents::Notifier#notify_ios_state_change failed: #{e.class} - #{e.message}")
    end

    def self.notify_android_state_change(release)
      return unless release.is_a?(PlayStoreRelease)
      return unless release.saved_change_to_status?

      old_status, new_status = release.saved_change_to_status
      return if old_status == new_status

      config = ANDROID_SIGNIFICANT_STATES[new_status]
      return unless config

      app = release.android_app
      return unless app

      organization = app.organization
      return unless organization

      app_label = app.name.presence || app.package_name
      message = "#{app_label} (version #{release.version_code}): #{config[:title]}"

      recipient_ids = organization.memberships.where(role: [ :admin, :developer ]).pluck(:user_id)
      recipient_ids << organization.owner_id if organization.owner_id
      recipient_ids = recipient_ids.compact.uniq

      recipient_ids.each do |user_id|
        user = User.find_by(id: user_id)
        next unless user&.notify_release_activity?

        create_notification(
          user_id: user_id,
          organization: organization,
          title: config[:title],
          message: message,
          resource: release,
          notification_type: "android_state_change:#{new_status}"
        )
      end
    rescue StandardError => e
      Rails.logger.error("ReleaseEvents::Notifier#notify_android_state_change failed: #{e.class} - #{e.message}")
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
      # Dedup collision on (user_id, resource_type, resource_id, notification_type, notification_date)
      # or other validation errors — skip silently so sync jobs don't fail.
      Rails.logger.warn("ReleaseEvents::Notifier skipped notification: #{e.message}")
    end
  end
end
