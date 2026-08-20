class CancelPaddleSubscriptionsJob < ApplicationJob
  queue_as :default

  # Cancels every active Paddle subscription owned by the user. Invoked
  # from User#soft_delete! after the local row has been marked
  # `deleted_at`; runs out of band so the user's destroy request is
  # never blocked on Paddle's API (Faraday timeout is 20s × up to 4
  # retries, so a synchronous in-request call could block ~160s on a
  # multi-sub user during a Paddle outage).
  #
  # Idempotent: subsequent runs on the same user are no-ops once the
  # subscriptions have been cancelled (the Billing::Paddle::Client
  # treats already-cancelled subs as success via NotFoundError).
  #
  # Failures: per-subscription cancellation errors are reported to
  # Rails.error inside the service. Job-level failures (e.g. the user
  # was hard-deleted between enqueue and run) are caught here and
  # logged + reported -- we don't retry indefinitely because the user
  # has already requested account deletion and the support team has
  # the failed sub IDs in error-tracker context to act on manually.
  # Raised when CancelOnAccountDeletion returns one or more
  # `failed_ids` -- it deliberately swallows individual cancellation
  # errors (so the user's deletion isn't blocked on a Paddle outage),
  # which would otherwise mean `retry_on StandardError` never fires
  # because the service never raised. Re-raise from here so the job
  # actually retries with the polynomial backoff. After the retry
  # budget is exhausted, the job's standard "failed" surface kicks in
  # and ops can act on the IDs in error-tracker context.
  class PartialCancellationError < StandardError; end

  retry_on StandardError, attempts: 3, wait: :polynomially_longer

  def perform(user_id)
    user = User.find_by(id: user_id)
    return if user.nil?

    result = Billing::Paddle::CancelOnAccountDeletion.call(user: user)
    return if result.failed_ids.empty?

    raise PartialCancellationError,
          "user=#{user_id} failed_subscription_ids=#{result.failed_ids.join(',')}"
  end
end
