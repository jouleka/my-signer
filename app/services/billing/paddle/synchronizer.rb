module Billing
  module Paddle
    class Synchronizer
      class IgnoredWebhookError < StandardError; end
      class UnmappableSubscriptionError < IgnoredWebhookError; end
      class UnknownPriceError < IgnoredWebhookError; end
      class QuarantinedOwnershipError < IgnoredWebhookError; end
      class OwnershipMismatchError < StandardError; end

      STATUS_MAP = {
        "active" => "active",
        "trialing" => "trialing",
        "past_due" => "past_due",
        "paused" => "paused",
        "canceled" => "cancelled"
      }.freeze

      def initialize(client: Client.new)
        @client = client
      end

      def synchronize_transaction!(transaction_id:, expected_user: nil, require_completed: false)
        transaction = @client.get_transaction(transaction_id)
        ensure_transaction_owned_by_expected_user!(transaction, expected_user:)
        completed = transaction_completed?(transaction)
        return { transaction: transaction, subscription: nil, billing_subscription: nil, completed: completed } if require_completed && !completed

        subscription_id = transaction["subscription_id"]
        return { transaction: transaction, subscription: nil, billing_subscription: nil, completed: completed } if subscription_id.blank?

        subscription = @client.get_subscription(subscription_id)
        billing_subscription = synchronize_subscription_payload!(subscription, occurred_at: transaction["updated_at"], expected_user: expected_user)

        { transaction: transaction, subscription: subscription, billing_subscription: billing_subscription, completed: completed }
      end

      def synchronize_subscription_payload!(subscription_payload, occurred_at: nil, expected_user: nil)
        subscription_id = subscription_payload["id"]
        raise ArgumentError, "Missing Paddle subscription ID" if subscription_id.blank?

        user = resolve_user(subscription_payload, expected_user: expected_user)
        raise UnmappableSubscriptionError, "No user mapped for Paddle subscription #{subscription_id}" unless user

        price_id = extract_price_id(subscription_payload)
        offering = Billing::PlanCatalog.fetch_by_price_id(price_id)
        raise UnknownPriceError, "Unknown Paddle price ID #{price_id}" unless offering

        billing_subscription = BillingSubscription.find_or_initialize_by(
          provider: Billing::Configuration.provider,
          provider_subscription_id: subscription_id
        )

        return billing_subscription if stale_event?(billing_subscription, occurred_at)

        payload_for_storage = subscription_payload.deep_dup
        payload_for_storage["last_event_occurred_at"] = occurred_at.to_s if occurred_at.present?

        billing_subscription.user = user
        billing_subscription.provider_plan_id = price_id
        billing_subscription.provider_product_id = subscription_payload.dig("items", 0, "product", "id") || Billing::Configuration.paddle_product_id
        billing_subscription.provider_customer_id = subscription_payload["customer_id"]
        billing_subscription.customer_email = subscription_payload.dig("custom_data", "customer_email") || billing_subscription.customer_email
        billing_subscription.plan_tier = offering.fetch(:plan_tier)
        billing_subscription.billing_interval = offering.fetch(:billing_interval)
        current_period_ends_at = parse_time(subscription_payload.dig("current_billing_period", "ends_at")) || parse_time(subscription_payload["next_billed_at"])
        scheduled_change_effective_at = parse_time(subscription_payload.dig("scheduled_change", "effective_at"))
        cancel_at_period_end = scheduled_cancel_at_period_end?(subscription_payload, current_period_ends_at:, scheduled_change_effective_at:)

        billing_subscription.status = normalize_status(subscription_payload["status"])
        billing_subscription.started_at = parse_time(subscription_payload["started_at"]) || parse_time(subscription_payload["created_at"]) || billing_subscription.started_at
        billing_subscription.current_period_started_at = parse_time(subscription_payload.dig("current_billing_period", "starts_at"))
        billing_subscription.current_period_ends_at = current_period_ends_at
        billing_subscription.cancelled_at = parse_time(subscription_payload["canceled_at"]) || (cancel_at_period_end ? scheduled_change_effective_at : nil)
        billing_subscription.cancel_at_period_end = cancel_at_period_end
        billing_subscription.last_synced_at = Time.current
        billing_subscription.provider_payload = payload_for_storage
        billing_subscription.save!

        BillingSubscription.recalculate_user_plan!(user)
        billing_subscription
      end

      private

      def ensure_transaction_owned_by_expected_user!(transaction_payload, expected_user:)
        return unless expected_user.present?

        user_id = custom_data_user_id(transaction_payload)
        if user_id.present? && user_id.to_s != expected_user.id.to_s
          raise OwnershipMismatchError, "Checkout does not belong to the signed-in user."
        end

        subscription_id = transaction_payload["subscription_id"]
        return if subscription_id.blank?

        existing = BillingSubscription.find_by(provider: Billing::Configuration.provider, provider_subscription_id: subscription_id)
        if existing.present? && existing.user_id != expected_user.id
          raise OwnershipMismatchError, "This subscription is already linked to another user."
        end
      end

      def resolve_user(subscription_payload, expected_user:)
        user_id = custom_data_user_id(subscription_payload)
        existing = BillingSubscription.find_by(provider: Billing::Configuration.provider, provider_subscription_id: subscription_payload["id"])

        if expected_user.present?
          if user_id.present? && user_id.to_s != expected_user.id.to_s
            raise OwnershipMismatchError, "Checkout does not belong to the signed-in user."
          end

          if existing.present? && existing.user_id != expected_user.id
            raise OwnershipMismatchError, "This subscription is already linked to another user."
          end

          return expected_user
        end

        # Webhook path (expected_user is nil): ownership MUST be derived from a
        # server-side mapping, never from client-controlled custom_data.user_id.
        resolve_user_for_webhook(subscription_payload, existing: existing, custom_data_user_id: user_id)
      end

      # On the webhook path the only trustworthy ownership signal is what the
      # server already recorded: the user bound to this subscription_id (from a
      # prior sync) or, for a first-ever subscription, the user the checkout
      # associated with this Paddle customer_id. custom_data.user_id is an
      # untrusted hint — accepted only when it agrees with the server-side
      # owner, and a contradiction quarantines the event (logged + no-op).
      def resolve_user_for_webhook(subscription_payload, existing:, custom_data_user_id:)
        subscription_id = subscription_payload["id"]
        customer_id = subscription_payload["customer_id"]

        # 1. Subscription already known: its recorded owner is authoritative.
        if existing.present?
          return guard_custom_data_hint!(
            server_owner_id: existing.user_id,
            custom_data_user_id: custom_data_user_id,
            subscription_id: subscription_id,
            source: "existing subscription",
            owner: existing.user
          )
        end

        # 2. First-ever subscription: bind from the customer_id the checkout
        #    already associated with a user server-side.
        server_owner = owner_from_customer_id(customer_id)
        if server_owner.present?
          return guard_custom_data_hint!(
            server_owner_id: server_owner.id,
            custom_data_user_id: custom_data_user_id,
            subscription_id: subscription_id,
            source: "customer_id mapping",
            owner: server_owner
          )
        end

        # 3. No server-side mapping exists at all. custom_data.user_id is only
        #    an untrusted hint here, but with nothing to contradict it (no prior
        #    checkout recorded this customer_id) it is the best available signal
        #    for an organic first subscription. Accept it if it resolves.
        if custom_data_user_id.present?
          User.find_by(id: custom_data_user_id)
        end
      end

      # Returns the server-side owner. If the client-supplied custom_data.user_id
      # disagrees with the recorded owner, the event is quarantined so an attacker
      # cannot rebind a victim's subscription by forging custom_data.user_id.
      def guard_custom_data_hint!(server_owner_id:, custom_data_user_id:, subscription_id:, source:, owner: nil)
        if custom_data_user_id.present? && custom_data_user_id.to_s != server_owner_id.to_s
          Rails.logger.warn(
            "[Billing::Paddle::Synchronizer] Quarantining webhook for subscription " \
            "#{subscription_id}: custom_data.user_id=#{custom_data_user_id} contradicts " \
            "server-side owner #{server_owner_id} (#{source}); ignoring event."
          )
          raise QuarantinedOwnershipError,
            "custom_data.user_id contradicts server-side owner for subscription #{subscription_id}"
        end

        owner || User.find_by(id: server_owner_id)
      end

      def owner_from_customer_id(customer_id)
        return nil if customer_id.blank?

        BillingSubscription
          .where(provider: Billing::Configuration.provider, provider_customer_id: customer_id)
          .order(created_at: :asc)
          .first
          &.user
      end

      # Paddle's client-side checkout serialises missing `user_id` as 0 (the
      # Stimulus Number value default). Treat 0/blank as "no mapping" so one
      # bad checkout doesn't poison every subsequent sync via ownership checks.
      def custom_data_user_id(payload)
        custom_data = payload["custom_data"] || {}
        raw = custom_data["user_id"] || custom_data[:user_id]
        return nil if raw.blank?
        return nil if raw.to_i.zero?

        raw
      end

      def extract_price_id(subscription_payload)
        item = Array(subscription_payload["items"]).first || {}
        item.dig("price", "id") || item["price_id"]
      end

      def normalize_status(status)
        STATUS_MAP[status.to_s] || "pending"
      end

      def transaction_completed?(transaction_payload)
        transaction_payload["status"].to_s == "completed"
      end

      def parse_time(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def stale_event?(billing_subscription, occurred_at)
        return false if occurred_at.blank? || billing_subscription.new_record?

        previous = billing_subscription.provider_payload["last_event_occurred_at"]
        return false if previous.blank?

        parse_time(previous) && parse_time(previous) > parse_time(occurred_at)
      end

      def scheduled_cancel_at_period_end?(subscription_payload, current_period_ends_at:, scheduled_change_effective_at:)
        return false unless subscription_payload.dig("scheduled_change", "action") == "cancel"
        return false if current_period_ends_at.blank? || scheduled_change_effective_at.blank?

        (scheduled_change_effective_at - current_period_ends_at).abs <= 5.minutes
      end
    end
  end
end
