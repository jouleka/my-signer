module GooglePlay
  class AnomalyNotifier
    def initialize(organization:, android_app:)
      @organization = organization
      @android_app = android_app
    end

    def check_and_notify(vitals_service)
      anomalies = vitals_service.anomalies(package_name: @android_app.package_name)
      return if anomalies.empty?

      anomalies.each do |anomaly|
        notify_anomaly(anomaly)
      end
    end

    private

    def notify_anomaly(anomaly)
      metric_name = anomaly[:metric_set]&.split("/")&.last&.titleize || "Quality"
      title = "#{metric_name} Anomaly Detected"
      message = "#{@android_app.name}: Google Play detected an anomaly in #{metric_name.downcase}."

      @organization.memberships.where(role: [ "owner", "admin" ]).find_each do |membership|
        user = User.find_by(id: membership.user_id)
        next unless user&.notify_release_activity?

        Notification.create(
          user_id: membership.user_id,
          organization_id: @organization.id,
          resource_type: "AndroidApp",
          resource_id: @android_app.id,
          notification_type: "vitals:anomaly:AndroidApp",
          title: title,
          message: message
        )
      rescue ActiveRecord::RecordNotUnique
        # Already notified today — skip
      end
    end
  end
end
