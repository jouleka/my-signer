module Billing
  module Paddle
    class ScheduledChangesController < ApplicationController
      include PaddleRedirectSafety

      before_action :authenticate_user!

      def destroy
        subscription = current_user.current_billing_subscription
        redirect_path = safe_redirect_path

        if subscription.blank? || subscription.scheduled_change.blank?
          redirect_to redirect_path, notice: "No scheduled change to cancel."
          return
        end

        if subscription.provider != Billing::Configuration.provider
          redirect_to redirect_path, alert: "This subscription is not managed by Paddle."
          return
        end

        schedule_kind = subscription.schedule_kind

        client = Billing::Paddle::Client.new
        updated = client.clear_scheduled_change(subscription.provider_subscription_id)

        Billing::Paddle::Synchronizer.new(client: client).synchronize_subscription_payload!(
          updated,
          occurred_at: updated["updated_at"].presence || Time.current.iso8601,
          expected_user: current_user
        )

        BillingSubscription.log_schedule_cleared_audit(user: current_user, schedule_kind: schedule_kind) if schedule_kind

        redirect_to redirect_path, notice: success_message(subscription, schedule_kind)
      rescue Billing::Paddle::Client::Error => e
        Rails.logger.warn("[Billing::Paddle::ScheduledChangesController] #{e.class}: #{e.message}")
        redirect_to redirect_path, alert: sanitize_paddle_error(e.message, fallback: "Unable to cancel the scheduled change right now.")
      rescue => e
        Rails.logger.error("[Billing::Paddle::ScheduledChangesController] #{e.class}: #{e.message}")
        redirect_to redirect_path, alert: "Unable to cancel the scheduled change right now."
      end

      private

      def success_message(subscription, schedule_kind)
        case schedule_kind
        when :cancel
          "Your #{subscription.plan_tier.titleize} plan will continue."
        when :downgrade
          "Your #{subscription.plan_tier.titleize} plan will continue. The scheduled downgrade was cancelled."
        else
          "Scheduled change cancelled."
        end
      end
    end
  end
end
