module Billing
  module Paddle
    module StoredSubscriptionPayload
      module_function

      # BillingSubscription only needs scheduled-change metadata and the last
      # processed event timestamp. Do not persist Paddle's complete response:
      # it can include customer details and custom data that are unnecessary
      # for entitlement decisions.
      def build(subscription_payload, event_occurred_at: nil)
        stored = {}
        scheduled_change = sanitize_scheduled_change(subscription_payload["scheduled_change"])
        stored["scheduled_change"] = scheduled_change if scheduled_change.present?
        stored["last_event_occurred_at"] = event_occurred_at.to_s if event_occurred_at.present?
        stored
      end

      def sanitize_scheduled_change(change)
        return nil unless change.is_a?(Hash)

        sanitized = {
          "action" => change["action"].to_s.presence,
          "effective_at" => change["effective_at"].to_s.presence
        }.compact

        items = Array(change["items"]).filter_map do |item|
          next unless item.is_a?(Hash)

          price_id = item.dig("price", "id") || item["price_id"]
          { "price" => { "id" => price_id.to_s } } if price_id.present?
        end
        sanitized["items"] = items if items.any?
        sanitized.presence
      end
      private_class_method :sanitize_scheduled_change
    end
  end
end
