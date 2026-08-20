module Billing
  module Paddle
    class WebhookProcessor
      def initialize(client: Client.new, synchronizer: nil)
        @client = client
        @synchronizer = synchronizer || Synchronizer.new(client: client)
      end

      def process!(payload)
        event_type = payload["event_type"].to_s
        data = payload["data"] || {}
        occurred_at = payload["occurred_at"]

        case event_type
        when "subscription.created", "subscription.updated", "subscription.activated", "subscription.trialing", "subscription.paused", "subscription.resumed", "subscription.canceled", "subscription.past_due"
          @synchronizer.synchronize_subscription_payload!(data, occurred_at: occurred_at)
          enqueue_status_notification(event_type, data)
        when "transaction.completed", "transaction.updated"
          subscription_id = data["subscription_id"]
          return if subscription_id.blank?

          subscription = @client.get_subscription(subscription_id)
          @synchronizer.synchronize_subscription_payload!(subscription, occurred_at: occurred_at)
        end
      end

      private

      def enqueue_status_notification(event_type, data)
        return unless %w[subscription.past_due subscription.canceled].include?(event_type)

        user_id = data.dig("custom_data", "user_id") || data["user_id"]
        user_id ||= lookup_user_id_from_subscription(data["id"])
        return if user_id.blank?

        event = event_type == "subscription.past_due" ? "payment_past_due" : "subscription_cancelled"
        BillingNotificationJob.perform_later(user_id: user_id, event: event, metadata: {})
      end

      def lookup_user_id_from_subscription(paddle_subscription_id)
        return if paddle_subscription_id.blank?

        BillingSubscription.find_by(
          provider: "paddle",
          provider_subscription_id: paddle_subscription_id
        )&.user_id
      end
    end
  end
end
