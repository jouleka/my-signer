module Billing
  module Paddle
    class SubscriptionChangePreviewsController < ApplicationController
      before_action :authenticate_user!

      def create
        result = applier.preview!
        render json: {
          ok: true,
          preview: Billing::SubscriptionChangePreviewPresenter.new(
            preview: result.preview,
            current_subscription: current_user.current_billing_subscription,
            target_tier: params.require(:plan_tier),
            target_interval: params.require(:billing_interval),
            policy: applier.policy
          ).to_h,
          warnings: result.warning_messages
        }
      rescue Billing::Paddle::SubscriptionChangeApplier::Error, Billing::Paddle::Client::Error => error
        Rails.logger.warn("[Billing::Paddle::SubscriptionChangePreviewsController] #{error.class}: #{error.message}")
        render json: { ok: false, error: error.message }, status: :unprocessable_content
      rescue => error
        Rails.logger.error("[Billing::Paddle::SubscriptionChangePreviewsController] #{error.class}: #{error.message}")
        render json: { ok: false, error: "Unable to preview this billing change right now." }, status: :internal_server_error
      end

      private

      def applier
        @applier ||= Billing::Paddle::SubscriptionChangeApplier.new(
          user: current_user,
          current_subscription: current_user.current_billing_subscription,
          target_tier: params.require(:plan_tier),
          target_interval: params.require(:billing_interval)
        )
      end
    end
  end
end
