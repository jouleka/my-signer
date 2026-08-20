require "openssl"

module Billing
  module Paddle
    class WebhookVerifier
      # 5s (the previous value) rejects valid webhooks on even minor clock
      # drift or retry backoff, dropping revenue events. 300s matches the
      # replay window Stripe and most other billing webhooks ship with; the
      # HMAC still pins payload+timestamp and Billing::Paddle::Synchronizer
      # enforces idempotency by Paddle event ID, so a replay within the
      # window is a no-op. Do not relax beyond 5 minutes without re-checking
      # that idempotency guarantee.
      DEFAULT_TOLERANCE_SECONDS = 300

      class << self
        def valid?(raw_body:, signature_header:, secret:, tolerance: DEFAULT_TOLERANCE_SECONDS)
          return false if raw_body.blank? || signature_header.blank? || secret.blank?

          timestamp, signatures = parse_signature_header(signature_header)
          return false if timestamp.blank? || signatures.empty?
          return false if tolerance && (Time.now.to_i - timestamp.to_i).abs > tolerance

          signed_payload = "#{timestamp}:#{raw_body}"
          expected_signature = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
          signatures.any? { |signature| secure_compare(expected_signature, signature) }
        end

        private

        def parse_signature_header(header)
          timestamp = nil
          signatures = []

          header.to_s.split(";").each do |segment|
            key, value = segment.split("=", 2)
            next if key.blank? || value.blank?

            case key
            when "ts"
              timestamp = value
            when "h1"
              signatures << value
            end
          end

          [ timestamp, signatures ]
        end

        def secure_compare(left, right)
          ActiveSupport::SecurityUtils.secure_compare(left, right)
        rescue ArgumentError
          false
        end
      end
    end
  end
end
