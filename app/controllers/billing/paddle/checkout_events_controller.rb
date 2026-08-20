module Billing
  module Paddle
    class CheckoutEventsController < ApplicationController
      include PaddleRedirectSafety

      before_action :authenticate_user!

      def create
        transaction_id = params[:transaction_id].to_s
        raise ActionController::ParameterMissing, :transaction_id if transaction_id.blank?

        result = synchronizer.synchronize_transaction!(transaction_id: transaction_id, expected_user: current_user, require_completed: true)
        billing_subscription = result[:billing_subscription]
        normalize_current_organization_context! if billing_subscription.present?

        redirect_url = safe_redirect_path(params[:return_to])

        if !result[:completed]
          flash[:notice] = "Purchase completed. We are waiting for Paddle to finish billing confirmation."
          render json: { ok: true, activated: false, redirect_url: redirect_url, retry_after_ms: 1200 }, status: :accepted
        elsif billing_subscription&.effective_tier.present? && billing_subscription.effective_tier != "free"
          flash[:notice] = "#{billing_subscription.plan_tier.titleize} plan is active."
          render json: { ok: true, activated: true, redirect_url: redirect_url }
        else
          flash[:notice] = "Purchase completed. We are refreshing your billing access."
          render json: { ok: true, activated: false, redirect_url: redirect_url, retry_after_ms: 1200 }, status: :accepted
        end
      rescue => error
        Rails.logger.error("[Billing::Paddle::CheckoutEventsController] #{error.class}: #{error.message}")
        render json: { ok: false, error: "Unable to confirm Paddle checkout yet." }, status: :unprocessable_content
      end

      private

      def synchronizer
        @synchronizer ||= Billing::Paddle::Synchronizer.new
      end
    end
  end
end
