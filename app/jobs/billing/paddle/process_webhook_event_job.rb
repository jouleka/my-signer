module Billing
  module Paddle
    class ProcessWebhookEventJob < ApplicationJob
      include AdvisoryLockable

      queue_as :default

      retry_on Billing::Paddle::Client::Error, wait: :polynomially_longer, attempts: 5
      retry_on StandardError, wait: :polynomially_longer, attempts: 3

      def perform(webhook_event_id)
        webhook_event = BillingWebhookEvent.find_by(id: webhook_event_id)
        return unless webhook_event&.verification_status_verified?

        with_advisory_lock("billing:paddle:webhook:event:#{webhook_event.id}") do
          webhook_event.reload
          return if webhook_event.processed_at.present?

          processor.process!(webhook_event.payload)
          mark_processed!(webhook_event)
        rescue Billing::Paddle::Client::NotFoundError, Billing::Paddle::Synchronizer::IgnoredWebhookError => error
          Rails.logger.warn("[Billing::Paddle::ProcessWebhookEventJob] Ignoring #{error.class.name.demodulize}: #{error.message}")
          mark_processed!(webhook_event)
        end
      end

      private

      def mark_processed!(webhook_event)
        webhook_event.update!(processed_at: Time.current)
      end

      def processor
        @processor ||= Billing::Paddle::WebhookProcessor.new
      end
    end
  end
end
