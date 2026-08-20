require "faraday"
require "faraday/retry"
require "json"

module Billing
  module Paddle
    class Client
      class Error < StandardError
        attr_reader :status, :code

        def initialize(message, status: nil, code: nil)
          @status = status
          @code = code
          super(message)
        end
      end

      class NotFoundError < Error; end

      # Paddle returns HTTP 400 with a structured `error.code` when the
      # caller tries to mutate a subscription that's already in a
      # terminal state ("subscription_is_canceled_action_invalid" for
      # cancel/update on a cancelled sub, "subscription_update_when_canceled"
      # for an update against a cancelled sub). The local desired-end-state
      # is "not billing this user", which is already true — surfacing
      # this as a distinct error class lets callers treat it as success
      # rather than retrying it as a transient failure.
      class AlreadyCancelledError < Error; end

      def initialize(api_key: Billing::Configuration.paddle_api_key, timeout: 20)
        @api_key = api_key
        raise ArgumentError, "Missing Paddle API key" if @api_key.blank?

        @conn = Faraday.new(url: Billing::Configuration.paddle_api_base) do |f|
          f.request :retry, max: 4, interval: 0.4, interval_randomness: 0.2, backoff_factor: 2,
                             retry_statuses: [ 429, 500, 502, 503, 504 ], methods: %i[get post patch]
          f.options.timeout = timeout
          f.adapter Faraday.default_adapter
        end
      end

      def get_transaction(transaction_id, include_relations: [])
        params = {}
        params[:include] = Array(include_relations).join(",") if include_relations.present?
        request(:get, "transactions/#{transaction_id}", params: params)
      end

      def get_subscription(subscription_id, include_relations: [])
        params = {}
        params[:include] = Array(include_relations).join(",") if include_relations.present?
        request(:get, "subscriptions/#{subscription_id}", params: params)
      end

      def preview_subscription_update(subscription_id, items:, proration_billing_mode:, on_payment_failure: nil, scheduled_change: :__keep__)
        request(:patch, "subscriptions/#{subscription_id}/preview", json: update_subscription_body(
          items: items,
          proration_billing_mode: proration_billing_mode,
          on_payment_failure: on_payment_failure,
          scheduled_change: scheduled_change
        ))
      end

      def update_subscription(subscription_id, items:, proration_billing_mode:, on_payment_failure: nil, scheduled_change: :__keep__)
        request(:patch, "subscriptions/#{subscription_id}", json: update_subscription_body(
          items: items,
          proration_billing_mode: proration_billing_mode,
          on_payment_failure: on_payment_failure,
          scheduled_change: scheduled_change
        ))
      end

      # Clears a pending scheduled_change (cancel, pause, or update) without
      # mutating items or proration. Callers that want to "undo" a schedule
      # should use this instead of update_subscription, which has mandatory
      # items/proration keywords geared toward plan changes.
      def clear_scheduled_change(subscription_id)
        request(:patch, "subscriptions/#{subscription_id}", json: { scheduled_change: nil })
      end

      # Cancels a Paddle subscription. Default `effective_from: "immediately"`
      # terminates the subscription right away (used by the account-deletion
      # path); pass "next_billing_period" for a graceful end-of-cycle cancel
      # consistent with the customer portal behavior. The synchronizer
      # picks up the cancellation on the next webhook either way.
      def cancel_subscription(subscription_id, effective_from: "immediately")
        request(:post, "subscriptions/#{subscription_id}/cancel",
                json: { effective_from: effective_from })
      end

      def create_customer_portal_session(customer_id, subscription_ids: nil)
        body = {}
        body[:subscription_ids] = Array(subscription_ids) if subscription_ids.present?
        request(:post, "customers/#{customer_id}/portal-sessions", json: body)
      end

      private

      def update_subscription_body(items:, proration_billing_mode:, on_payment_failure:, scheduled_change:)
        body = {
          items: items,
          proration_billing_mode: proration_billing_mode
        }
        body[:on_payment_failure] = on_payment_failure if on_payment_failure.present?
        body[:scheduled_change] = scheduled_change unless scheduled_change == :__keep__
        body
      end

      def request(method, path, params: nil, json: nil)
        response = @conn.public_send(method) do |req|
          req.url(path)
          req.headers["Authorization"] = "Bearer #{@api_key}"
          req.headers["Accept"] = "application/json"
          req.headers["Content-Type"] = "application/json" if json
          req.params.update(params) if params.present?
          req.body = JSON.dump(json) if json
        end

        parse!(response)
      end

      def parse!(response)
        status = response.status.to_i
        body = response.body.present? ? JSON.parse(response.body) : {}
        return body.fetch("data", body) if status.between?(200, 299)

        errors = extract_errors(body)
        code = extract_code(body)
        message = errors.presence&.join("; ") || "HTTP #{status}"

        raise error_class_for(status, code).new(message, status: status, code: code)
      rescue JSON::ParserError
        raise Error.new("Invalid JSON response from Paddle (HTTP #{status})", status: status)
      end

      def extract_errors(body)
        messages = []

        [ body["error"], body["errors"] ].each do |value|
          case value
          when Array
            value.each { |entry| messages.concat(error_messages_for(entry)) }
          when nil
            next
          else
            messages.concat(error_messages_for(value))
          end
        end

        messages.compact_blank.uniq
      end

      def error_messages_for(entry)
        case entry
        when Hash
          [ entry["detail"], entry["message"], entry["code"] ]
        else
          [ entry.to_s ]
        end
      end

      # Paddle's "this subscription is already in a terminal state"
      # response is HTTP 400 with a structured `error.code`. Mapping
      # those codes to a dedicated exception class means callers like
      # `CancelOnAccountDeletion` can treat them as success (the
      # desired end state is already achieved) instead of retrying
      # them as transient failures.
      ALREADY_CANCELLED_CODES = %w[
        subscription_is_canceled_action_invalid
        subscription_update_when_canceled
      ].freeze

      def error_class_for(status, code = nil)
        return NotFoundError if status == 404
        return AlreadyCancelledError if ALREADY_CANCELLED_CODES.include?(code)

        Error
      end

      # Paddle's error envelope is `{ "error": { "code": "...", ... } }`
      # for single-error responses or `{ "errors": [{ "code": "...", ... }] }`
      # for multi-error. Pull the first code we find; pluralizing mass
      # cancellation isn't a flow this client handles today.
      def extract_code(body)
        single = body["error"]
        return single["code"] if single.is_a?(Hash) && single["code"].is_a?(String)

        many = body["errors"]
        if many.is_a?(Array)
          first = many.find { |entry| entry.is_a?(Hash) && entry["code"].is_a?(String) }
          return first["code"] if first
        end

        nil
      end
    end
  end
end
