module Billing
  class SubscriptionChangePolicy
    UnsupportedTransitionError = Class.new(StandardError)

    attr_reader :current_subscription, :target_tier, :target_interval

    def initialize(current_subscription:, target_tier:, target_interval:)
      @current_subscription = current_subscription
      @target_tier = target_tier.to_s
      @target_interval = target_interval.to_s
    end

    def supported?
      transition.present?
    end

    def label
      transition&.fetch(:label)
    end

    def message
      transition&.fetch(:message)
    end

    def proration_billing_mode
      transition&.fetch(:proration_billing_mode)
    end

    def on_payment_failure
      transition&.fetch(:on_payment_failure)
    end

    def scheduled_change?
      transition&.fetch(:scheduled, false)
    end

    def immediate_change?
      transition&.fetch(:immediate, false)
    end

    def clear_scheduled_change?
      transition&.fetch(:clear_scheduled_change, false)
    end

    def items_unchanged?
      transition&.fetch(:items_unchanged, false)
    end

    def target_price_id
      Billing::Configuration.paddle_price_id_for(tier: target_tier, interval: target_interval)
    end

    def update_payload
      raise UnsupportedTransitionError, unsupported_reason unless supported?

      # items_unchanged? transitions (Keep-plan undo) go through
      # Client#clear_scheduled_change in the applier; update_payload is only
      # consumed for item-changing transitions, so always include items here.
      {
        items: [ { price_id: target_price_id, quantity: 1 } ],
        proration_billing_mode: proration_billing_mode,
        on_payment_failure: on_payment_failure
      }.compact
    end

    def unsupported_reason
      return "Unsupported target plan." if target_price_id.blank?
      return "You are already on that plan." if current_plan_match?
      return "This subscription change is not supported yet." unless current_subscription.present?
      return "This subscription change is not supported for trial subscriptions." if current_subscription.status_trialing?
      return "This subscription change is not supported yet." unless supported?

      "This subscription change is not supported yet."
    end

    private

    def transition
      @transition ||= compute_transition
    end

    def compute_transition
      return nil if target_price_id.blank?
      return nil unless current_subscription.present?
      return nil if current_subscription.status_trialing?

      # Keep current plan: user is on target plan AND a schedule is pending → undo the schedule.
      if current_plan_match? && schedule_pending?
        return {
          label: "Keep #{current_subscription.plan_tier.titleize} plan",
          message: "Your scheduled change will be cancelled. You'll continue on #{current_subscription.plan_tier.titleize} #{current_subscription.billing_interval.titleize}.",
          proration_billing_mode: nil,
          on_payment_failure: nil,
          immediate: true,
          scheduled: false,
          clear_scheduled_change: true,
          items_unchanged: true
        }
      end

      # Same plan with no pending schedule → no change offered.
      return nil if current_plan_match?

      # Pro → Team same interval (monthly→monthly or yearly→yearly).
      if current_subscription.plan_tier == "pro" &&
         target_tier == "team" &&
         target_interval == current_subscription.billing_interval
        return {
          label: "Upgrade now",
          message: "Team access applies immediately.",
          proration_billing_mode: "prorated_immediately",
          on_payment_failure: "prevent_change",
          immediate: true,
          scheduled: false,
          clear_scheduled_change: false,
          items_unchanged: false
        }
      end

      # Pro monthly → Team yearly (cross-interval upgrade).
      if current_subscription.plan_tier == "pro" &&
         target_tier == "team" &&
         current_subscription.billing_interval == "monthly" &&
         target_interval == "yearly"
        return {
          label: "Upgrade now",
          message: "Team yearly access applies immediately.",
          proration_billing_mode: "prorated_immediately",
          on_payment_failure: "prevent_change",
          immediate: true,
          scheduled: false,
          clear_scheduled_change: false,
          items_unchanged: false
        }
      end

      # Same tier, monthly → yearly. When a schedule is pending we also
      # clear it (atomic: new items + do_not_bill + scheduled_change: null).
      if current_subscription.plan_tier == target_tier &&
         current_subscription.billing_interval == "monthly" &&
         target_interval == "yearly"
        return {
          label: "Switch to yearly",
          message: "#{target_tier.titleize} yearly applies now. No immediate charge.#{schedule_pending? ? ' Any scheduled change is cancelled.' : ''}",
          proration_billing_mode: "do_not_bill",
          on_payment_failure: "prevent_change",
          immediate: true,
          scheduled: false,
          clear_scheduled_change: schedule_pending?,
          items_unchanged: false
        }
      end

      # Team → Pro same interval (scheduled downgrade). When a cancel is
      # already scheduled, Paddle's single-slot scheduled_change is replaced
      # atomically by the new PATCH — no explicit clear needed.
      if current_subscription.plan_tier == "team" &&
         target_tier == "pro" &&
         target_interval == current_subscription.billing_interval
        return {
          label: "Downgrade at renewal",
          message: current_subscription.scheduled_change_cancel? ?
            "Pro access starts on the next renewal. Your scheduled cancellation is replaced." :
            "Pro access starts on the next renewal. Any downgrade credit is applied on that renewal.",
          proration_billing_mode: "prorated_next_billing_period",
          on_payment_failure: "prevent_change",
          immediate: false,
          scheduled: true,
          clear_scheduled_change: false,
          items_unchanged: false
        }
      end

      nil
    end

    def current_plan_match?
      current_subscription&.plan_tier == target_tier && current_subscription&.billing_interval == target_interval
    end

    def schedule_pending?
      current_subscription&.scheduled_change_cancel? || current_subscription&.scheduled_plan_change?
    end
  end
end
