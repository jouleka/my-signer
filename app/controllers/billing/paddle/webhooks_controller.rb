module Billing
  module Paddle
    class WebhooksController < ActionController::Base
      # Paddle cannot provide a Rails CSRF token. Use a null session and then
      # authenticate the exact raw body with Paddle's signed webhook header.
      protect_from_forgery with: :null_session

      def create
        raw_body = request.raw_post
        signature = request.headers["Paddle-Signature"].to_s

        unless Billing::Paddle::WebhookVerifier.valid?(
          raw_body: raw_body,
          signature_header: signature,
          secret: Billing::Configuration.paddle_webhook_secret
        )
          return render json: { error: "invalid_signature" }, status: :unauthorized
        end

        payload = JSON.parse(raw_body)
        webhook_event = find_or_build_webhook_event(payload)

        if webhook_event.processed_at.present?
          return render json: { ok: true, duplicate: true }
        end

        webhook_event.event_type = payload["event_type"]
        webhook_event.verification_status = "verified"
        webhook_event.payload = payload
        webhook_event.save!

        Billing::Paddle::ProcessWebhookEventJob.perform_later(webhook_event.id)

        render json: { ok: true, queued: true }
      rescue JSON::ParserError
        render json: { error: "invalid_json" }, status: :bad_request
      rescue ActiveRecord::RecordNotUnique
        webhook_event = BillingWebhookEvent.find_by!(provider: Billing::Configuration.provider, event_id: payload["event_id"])
        Billing::Paddle::ProcessWebhookEventJob.perform_later(webhook_event.id) if webhook_event.processed_at.blank?
        render json: { ok: true, duplicate: webhook_event.processed_at.present?, queued: webhook_event.processed_at.blank? }
      rescue => error
        Rails.logger.error("[Billing::Paddle::WebhooksController] #{error.class}: #{error.message}")
        render json: { error: "processing_failed" }, status: :service_unavailable
      end

      private

      def find_or_build_webhook_event(payload)
        BillingWebhookEvent.find_or_initialize_by(
          provider: Billing::Configuration.provider,
          event_id: payload["event_id"]
        )
      end
    end
  end
end
