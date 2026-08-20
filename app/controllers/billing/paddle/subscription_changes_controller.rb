module Billing
  module Paddle
    class SubscriptionChangesController < ApplicationController
      include PaddleRedirectSafety

      GENERIC_ERROR = "Unable to change the subscription right now.".freeze
      private_constant :GENERIC_ERROR

      before_action :authenticate_user!

      # `redirect_to` (not `redirect_back`) so the destination is always the
      # value safe_redirect_path already validated. redirect_back would
      # prefer HTTP_REFERER and only fall back if referer was absent/cross-
      # origin; Rails 8's raise_on_open_redirects default blocks the cross-
      # origin case, but relying on that framework default for a security-
      # sensitive branch is fragile.
      def create
        result = applier.apply!
        normalize_current_organization_context!
        redirect_path = safe_redirect_path(params[:return_to])

        notice = [ result.message, result.warning_messages.presence&.join(" ") ].compact.join(" ")
        redirect_to redirect_path, notice: notice
      rescue Billing::Paddle::SubscriptionChangeApplier::Error, Billing::Paddle::Client::Error => error
        Rails.logger.warn("[Billing::Paddle::SubscriptionChangesController] #{error.class}: #{error.message}")
        redirect_to safe_redirect_path(params[:return_to]),
                    alert: sanitize_paddle_error(error.message, fallback: GENERIC_ERROR)
      rescue => error
        Rails.logger.error("[Billing::Paddle::SubscriptionChangesController] #{error.class}: #{error.message}")
        redirect_to safe_redirect_path(params[:return_to]), alert: GENERIC_ERROR
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
