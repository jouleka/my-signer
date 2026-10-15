module Billing
  module Paddle
    class SubscriptionChangeApplier
      Result = Struct.new(
        :billing_subscription,
        :preview,
        :audit,
        :message,
        :warning_messages,
        keyword_init: true
      )

      class Error < StandardError; end

      def initialize(user:, current_subscription:, target_tier:, target_interval:, client: Client.new, synchronizer: nil)
        @user = user
        @current_subscription = current_subscription
        @target_tier = target_tier.to_s
        @target_interval = target_interval.to_s
        @client = client
        @synchronizer = synchronizer || Synchronizer.new(client: client)
        @policy = Billing::SubscriptionChangePolicy.new(
          current_subscription: current_subscription,
          target_tier: target_tier,
          target_interval: target_interval
        )
      end

      def apply!
        validate_transition!

        # Invariant: every items_unchanged transition MUST be immediate (Keep-plan
        # undo clears the schedule NOW and the user keeps their current plan NOW).
        # If a future policy branch sets items_unchanged with immediate:false,
        # the persist path below would skip synchronization and leave the user's
        # plan_tier stale. Catch that design bug here rather than corrupting state.
        if @policy.items_unchanged? && !@policy.immediate_change?
          raise Error, "Invalid policy: items_unchanged transitions must be immediate."
        end

        if @policy.items_unchanged?
          # Keep-plan undo: no items, no proration, no preview — just null the schedule.
          updated_subscription = @client.clear_scheduled_change(live_subscription["id"])
          preview = {}
        else
          preview = @client.preview_subscription_update(live_subscription["id"], **subscription_update_payload)
          updated_subscription = @client.update_subscription(live_subscription["id"], **subscription_update_payload)
        end

        billing_subscription =
          if @policy.immediate_change?
            @synchronizer.synchronize_subscription_payload!(
              updated_subscription,
              occurred_at: updated_subscription["updated_at"] || Time.current.iso8601,
              expected_user: @user
            )
          else
            persist_scheduled_change!(updated_subscription)
          end

        audit = build_transition_audit

        Result.new(
          billing_subscription: billing_subscription,
          preview: preview,
          audit: audit,
          message: success_message_for(billing_subscription),
          warning_messages: audit.warning_messages
        )
      rescue Billing::SubscriptionChangePolicy::UnsupportedTransitionError => error
        raise Error, error.message
      end

      def preview!
        validate_transition!
        audit = build_transition_audit

        paddle_preview =
          if @policy.items_unchanged?
            {} # no preview needed — presenter falls through to $0 today
          else
            @client.preview_subscription_update(live_subscription["id"], **subscription_update_payload)
          end

        Result.new(
          billing_subscription: current_subscription,
          preview: paddle_preview,
          audit: audit,
          message: @policy.message,
          warning_messages: audit.warning_messages
        )
      rescue Billing::SubscriptionChangePolicy::UnsupportedTransitionError => error
        raise Error, error.message
      end

      def policy
        @policy
      end

      private

      attr_reader :current_subscription

      def validate_transition!
        raise Error, "No active Paddle subscription found." if current_subscription.blank?
        raise Error, "This subscription is not managed in Paddle." if current_subscription.provider != Billing::Configuration.provider
        raise Error, "Missing Paddle subscription reference." if current_subscription.provider_subscription_id.blank?
        raise Error, @policy.unsupported_reason unless @policy.supported?

        status = live_subscription["status"].to_s
        raise Error, "This subscription is past due. Resolve billing in Paddle first." if status == "past_due"
        raise Error, "This subscription is paused. Resume it in Paddle before changing plans." if status == "paused"
        raise Error, "This subscription is trialing. Subscription changes for trial plans are not supported yet." if status == "trialing"
        raise Error, "Subscription changes are temporarily unavailable in the last 30 minutes before renewal." if renewal_window_locked?
        raise Error, "Remove the scheduled pause in Paddle before changing this subscription." if scheduled_pause_conflict?
      end

      def renewal_window_locked?
        renewal_time = parse_time(live_subscription["next_billed_at"]) || current_subscription.current_period_ends_at
        renewal_time.present? && renewal_time <= 30.minutes.from_now
      end

      def scheduled_pause_conflict?
        live_subscription.dig("scheduled_change", "action") == "pause"
      end

      def build_transition_audit
        Pricing::PlanTransitionAudit.new(user: @user, target_tier: @target_tier)
      end

      def success_message_for(billing_subscription)
        if interval_change_applied?(billing_subscription)
          message = "#{@target_tier.titleize} #{@target_interval.titleize} is active. No immediate charge was made."
          clear_scheduled_cancellation? ? "#{message} Scheduled cancellation was removed." : message
        elsif target_plan_applied?(billing_subscription) && @policy.immediate_change?
          message = "#{billing_subscription.plan_tier.titleize} plan is active."
          clear_scheduled_cancellation? ? "#{message} Scheduled cancellation was removed." : message
        elsif billing_subscription.scheduled_change_effective_at.present?
          "#{@target_tier.titleize} #{@target_interval.titleize} is scheduled for #{I18n.l(billing_subscription.scheduled_change_effective_at, format: :long)}."
        else
          "#{@target_tier.titleize} #{@target_interval.titleize} change was submitted."
        end
      end

      def live_subscription
        @live_subscription ||= @client.get_subscription(current_subscription.provider_subscription_id)
      end

      def persist_scheduled_change!(updated_subscription)
        payload_for_storage = StoredSubscriptionPayload.build(
          updated_subscription,
          event_occurred_at: updated_subscription["updated_at"].presence ||
            current_subscription.provider_payload["last_event_occurred_at"]
        )

        current_subscription.assign_attributes(
          provider_customer_id: updated_subscription["customer_id"] || current_subscription.provider_customer_id,
          provider_payload: payload_for_storage,
          last_synced_at: Time.current
        )
        current_subscription.current_period_ends_at = parse_time(updated_subscription.dig("current_billing_period", "ends_at")) || parse_time(updated_subscription["next_billed_at"]) || current_subscription.current_period_ends_at
        current_subscription.save!
        current_subscription
      end

      def parse_time(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def interval_change_applied?(billing_subscription)
        current_subscription.plan_tier == @target_tier &&
          current_subscription.billing_interval != @target_interval &&
          target_plan_applied?(billing_subscription)
      end

      def target_plan_applied?(billing_subscription)
        billing_subscription.plan_tier == @target_tier &&
          billing_subscription.billing_interval == @target_interval
      end

      def subscription_update_payload
        @subscription_update_payload ||= begin
          payload = @policy.update_payload.dup
          payload[:items] = merged_subscription_items
          payload[:scheduled_change] = nil if clear_scheduled_cancellation?
          payload
        end
      end

      def merged_subscription_items
        items = Array(live_subscription["items"])
        raise Error, "Missing Paddle subscription items." if items.blank?

        target_index = current_plan_item_index(items)
        raise Error, "Unable to identify the current plan item for this subscription." if target_index.nil?

        items.map.with_index do |item, index|
          if index == target_index
            merged_target_item(item)
          else
            preserved_item(item)
          end
        end
      end

      def current_plan_item_index(items)
        matching_indexes = items.each_index.select { |index| current_plan_item?(items[index]) }
        return matching_indexes.first if matching_indexes.one?
        return 0 if matching_indexes.empty? && items.one?

        nil
      end

      def current_plan_item?(item)
        price_id = item.dig("price", "id") || item["price_id"]
        product_id = item.dig("product", "id") || item["product_id"] || item.dig("price", "product_id")

        return true if current_subscription.provider_plan_id.present? && price_id == current_subscription.provider_plan_id
        return true if current_subscription.provider_product_id.present? && product_id == current_subscription.provider_product_id

        false
      end

      def merged_target_item(item)
        quantity = item["quantity"].presence || 1
        {
          price_id: @policy.target_price_id,
          quantity: quantity
        }
      end

      def preserved_item(item)
        price_id = item.dig("price", "id") || item["price_id"]
        payload =
          if price_id.present?
            { price_id: price_id }
          elsif item["price"].is_a?(Hash)
            { price: item["price"].deep_dup }
          else
            raise Error, "Unable to preserve a recurring subscription item without a price ID."
          end

        payload[:quantity] = item["quantity"] if item["quantity"].present?
        payload
      end

      def clear_scheduled_cancellation?
        @policy.immediate_change? && live_subscription.dig("scheduled_change", "action") == "cancel"
      end
    end
  end
end
