module Billing
  module Paddle
    # Cancels every active Paddle subscription a user owns, for use from
    # the account-deletion path. Called from User#soft_delete! before the
    # local row is marked deleted_at.
    #
    # Behavior:
    # - Loops through `user.billing_subscriptions.where(status: CANCELLABLE_STATUSES)`
    #   and POSTs `/subscriptions/:id/cancel?effective_from=immediately`.
    #   The status set is broader than `active_for_entitlements`
    #   (trialing/active/past_due) on purpose -- see the doc on
    #   CANCELLABLE_STATUSES below.
    # - Already-cancelled subscriptions on Paddle's side surface as
    #   either HTTP 404 (subscription deleted) OR HTTP 400 with code
    #   `subscription_is_canceled_action_invalid` /
    #   `subscription_update_when_canceled`. Both raise
    #   `NotFoundError` / `AlreadyCancelledError` from `Client`; we
    #   swallow both because the desired end state ("not billing this
    #   user") is already achieved. Treating the HTTP-400 case as a
    #   generic failure would (a) flag idempotent retries as
    #   `failed_ids`, (b) make `CancelPaddleSubscriptionsJob` re-raise
    #   and retry 3× via `retry_on StandardError`, and (c) breach the
    #   "idempotent on subsequent runs" claim above.
    # - Other errors are reported to Rails.error and logged, but do NOT
    #   abort the soft-delete: the user has explicitly asked us to delete
    #   their account, and a Paddle outage must not leave them with an
    #   undeletable account. Support can drive a manual cancel via the
    #   Paddle dashboard / CLI; the failed_subscription_ids in the
    #   returned struct gives ops the IDs to act on.
    #
    # Returns Result(cancelled_ids:, failed_ids:). Idempotent: subsequent
    # calls on a user with no active subs return Result.new([], []).
    class CancelOnAccountDeletion
      Result = Struct.new(:cancelled_ids, :failed_ids, keyword_init: true)

      def self.call(user:, client: Client.new)
        new(user: user, client: client).call
      end

      def initialize(user:, client:)
        @user = user
        @client = client
      end

      # Statuses we attempt to cancel on Paddle's side. Broader than
      # `active_for_entitlements` (trialing/active/past_due) on purpose
      # -- a `pending` sub (just created, awaiting first webhook) and
      # a `paused` sub will both keep charging or resume charging if
      # left alone, so they need to be cancelled too. `cancelled` and
      # `expired` are skipped because Paddle has already terminated
      # them.
      CANCELLABLE_STATUSES = %w[pending trialing active past_due paused].freeze

      def call
        cancelled = []
        failed = []

        @user.billing_subscriptions.where(status: CANCELLABLE_STATUSES).find_each do |sub|
          paddle_id = sub.provider_subscription_id
          next if paddle_id.blank?
          next unless sub.provider == "paddle"

          begin
            @client.cancel_subscription(paddle_id, effective_from: "immediately")
            cancelled << paddle_id
          rescue Client::NotFoundError, Client::AlreadyCancelledError
            # Already cancelled / deleted on Paddle's side -- desired end
            # state already achieved, treat as success. NotFoundError
            # covers HTTP 404 (the sub was hard-deleted on Paddle's side);
            # AlreadyCancelledError covers HTTP 400 with the canonical
            # "this is a cancelled-state-only sub" Paddle error codes.
            cancelled << paddle_id
          rescue => e
            failed << paddle_id
            Rails.logger.error(
              "[CancelOnAccountDeletion] user=#{@user.id} sub=#{paddle_id} #{e.class}: #{e.message}"
            )
            Rails.error.report(
              e,
              handled: true,
              severity: :error,
              context: {
                service: self.class.name,
                user_id: @user.id,
                paddle_subscription_id: paddle_id
              }
            )
          end
        end

        Result.new(cancelled_ids: cancelled, failed_ids: failed)
      end
    end
  end
end
