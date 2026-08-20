module Billing
  class Configuration
    PROVIDER = "paddle".freeze
    DEFAULT_PADDLE_ENV = "sandbox".freeze
    REQUIRED_PADDLE_CHECKOUT_ENV_KEYS = %w[
      PADDLE_CLIENT_SIDE_TOKEN
      PADDLE_PRO_MONTHLY_PRICE_ID
      PADDLE_PRO_YEARLY_PRICE_ID
      PADDLE_TEAM_MONTHLY_PRICE_ID
      PADDLE_TEAM_YEARLY_PRICE_ID
    ].freeze
    REQUIRED_PADDLE_BACKEND_ENV_KEYS = %w[
      PADDLE_API_KEY
    ].freeze
    OPTIONAL_PADDLE_ENV_KEYS = %w[
      PADDLE_PRODUCT_ID
      PADDLE_WEBHOOK_SECRET
      PADDLE_NOTIFICATION_SETTING_ID
    ].freeze

    class << self
      def provider
        ENV["BILLING_PROVIDER"].presence || PROVIDER
      end

      def provider_name
        provider.to_s.titleize
      end

      def paddle_environment
        ENV["PADDLE_ENV"].presence || DEFAULT_PADDLE_ENV
      end

      def paddle_sandbox?
        paddle_environment == "sandbox"
      end

      def paddle_live?
        paddle_environment == "live"
      end

      def paddle_api_base
        paddle_sandbox? ? "https://sandbox-api.paddle.com" : "https://api.paddle.com"
      end

      def paddle_client_side_token
        ENV["PADDLE_CLIENT_SIDE_TOKEN"].presence
      end

      def paddle_api_key
        ENV["PADDLE_API_KEY"].presence
      end

      def paddle_webhook_secret
        ENV["PADDLE_WEBHOOK_SECRET"].presence
      end

      def paddle_product_id
        ENV["PADDLE_PRODUCT_ID"].presence
      end

      def paddle_notification_setting_id
        ENV["PADDLE_NOTIFICATION_SETTING_ID"].presence
      end

      def paddle_price_ids
        {
          "pro" => {
            "monthly" => ENV["PADDLE_PRO_MONTHLY_PRICE_ID"].presence,
            "yearly" => ENV["PADDLE_PRO_YEARLY_PRICE_ID"].presence
          },
          "team" => {
            "monthly" => ENV["PADDLE_TEAM_MONTHLY_PRICE_ID"].presence,
            "yearly" => ENV["PADDLE_TEAM_YEARLY_PRICE_ID"].presence
          }
        }
      end

      def paddle_price_id_for(tier:, interval:)
        paddle_price_ids.dig(tier.to_s, interval.to_s)
      end

      def paddle_checkout_ready?
        return false unless provider == PROVIDER
        return false unless paddle_credentials_match_environment?

        REQUIRED_PADDLE_CHECKOUT_ENV_KEYS.all? { |key| ENV[key].present? }
      end

      def paddle_backend_ready?
        return false unless provider == PROVIDER
        return false unless paddle_credentials_match_environment?

        REQUIRED_PADDLE_BACKEND_ENV_KEYS.all? { |key| ENV[key].present? }
      end

      def paddle_webhooks_ready?
        paddle_webhook_secret.present?
      end

      def paddle_credentials_match_environment?
        token = paddle_client_side_token
        api_key = paddle_api_key

        token_ok =
          if token.blank?
            false
          elsif paddle_sandbox?
            token.start_with?("test_")
          else
            token.start_with?("live_")
          end

        api_key_ok =
          if api_key.blank?
            false
          elsif paddle_sandbox?
            api_key.start_with?("pdl_sdbx_apikey_")
          else
            api_key.start_with?("pdl_live_apikey_")
          end

        token_ok && api_key_ok
      end

      def self_serve_checkout_available?
        paddle_checkout_ready? && paddle_backend_ready?
      end
    end
  end
end
