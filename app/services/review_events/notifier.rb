module ReviewEvents
  class Notifier
    # Sends in-app notifications for new negative reviews (1-2 stars).
    # Follows the same pattern as ReleaseEvents::Notifier.
    # Includes per-day dedup via Notification's uniqueness validation.
    def self.notify_new_review(review)
      return unless review.is_a?(AppReview)
      return unless review.rating <= 2

      organization = review.organization
      return unless organization

      platform_label = review.apple? ? "App Store" : "Google Play"
      app = review.reviewable
      app_label = app.respond_to?(:name) ? (app.name.presence || app.try(:bundle_id) || app.try(:package_name)) : "App"

      title = "Negative Review on #{platform_label}"
      message = "#{app_label}: #{review.rating}-star review from #{review.reviewer_name || 'Anonymous'}"

      notification_type = "review:new_negative:#{review.reviewable_type}"

      recipient_ids = organization.memberships.where(role: %i[admin owner]).pluck(:user_id)
      recipient_ids << organization.owner_id if organization.owner_id
      recipient_ids = recipient_ids.compact.uniq

      recipient_ids.each do |user_id|
        user = User.find_by(id: user_id)
        next unless user&.notify_release_activity?

        create_notification(
          user_id: user_id,
          organization: organization,
          title: title,
          message: message,
          resource: review,
          notification_type: notification_type
        )
      end
    rescue StandardError => e
      Rails.logger.error("ReviewEvents::Notifier#notify_new_review failed: #{e.class} - #{e.message}")
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
      Rails.logger.warn("ReviewEvents::Notifier skipped notification: #{e.message}")
    end
  end
end
