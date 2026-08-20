module Billing
  module Paddle
    class PortalSessionsController < ApplicationController
      before_action :authenticate_user!

      def create
        subscription = current_user.current_billing_subscription
        redirect_back fallback_location: fallback_location, alert: "No active subscription found." and return if subscription.blank?
        redirect_back fallback_location: fallback_location, alert: "This subscription cannot be managed online yet." and return if subscription.provider != Billing::Configuration.provider
        redirect_back fallback_location: fallback_location, alert: "Billing customer details are not available yet." and return if subscription.provider_customer_id.blank?

        url =
          case params[:purpose].to_s
          when "cancel"
            live_subscription.dig("management_urls", "cancel")
          when "update_payment_method"
            live_subscription.dig("management_urls", "update_payment_method")
          else
            session = client.create_customer_portal_session(subscription.provider_customer_id)
            session.dig("urls", "general", "overview")
          end
        redirect_back fallback_location: fallback_location, alert: "Billing management is temporarily unavailable." and return if url.blank?

        Audit::Logger.log(
          action: "billing_portal_accessed",
          organization: current_organization,
          request: request
        )
        redirect_to url, allow_other_host: true
      rescue => error
        Rails.logger.error("[Billing::Paddle::PortalSessionsController] #{error.class}: #{error.message}")
        redirect_back fallback_location: fallback_location, alert: "Unable to open billing management right now."
      end

      private

      def client
        @client ||= Billing::Paddle::Client.new
      end

      def live_subscription
        @live_subscription ||= client.get_subscription(current_user.current_billing_subscription.provider_subscription_id)
      end

      def fallback_location
        pricing_path
      end
    end
  end
end
