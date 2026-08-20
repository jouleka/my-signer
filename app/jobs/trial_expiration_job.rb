class TrialExpirationJob < ApplicationJob
  queue_as :default

  # Runs daily to downgrade users whose 14-day reverse trial has ended.
  # Only downgrades users who:
  #   - Have a non-null trial_ends_at in the past
  #   - Are currently on plan_tier=pro (from trial)
  #   - Do NOT have an active Paddle subscription
  #
  # A user who upgraded via Paddle during the trial has their trial fields
  # cleared by BillingSubscription.recalculate_user_plan! -- so they won't
  # match this query.
  def perform
    expired_trial_users.find_each do |user|
      expire_trial!(user)
    end
  end

  private

  def expired_trial_users
    User
      .where("trial_ends_at IS NOT NULL AND trial_ends_at < ?", Time.current)
      .where(plan_tier: User.plan_tiers[:pro])
      .where.not(
        id: BillingSubscription.active_for_entitlements.select(:user_id)
      )
  end

  def expire_trial!(user)
    # Re-check conditions under a row lock to avoid a race with a concurrent
    # Paddle webhook that may have just upgraded this user during our batch
    # window. Without this, a user who upgrades at the exact moment this job
    # runs could be silently downgraded back to free.
    #
    # Audit events are emitted inside the same transaction so the audit
    # row(s) and the plan_tier change commit together at the SQL level --
    # eliminating the previous "drift window" where the plan was downgraded
    # but the audit write hadn't run yet (process death between them would
    # leave an orphan downgrade with no audit trail).
    #
    # Note: Audit::Logger#call has its own top-level rescue (see
    # app/services/audit/logger.rb). If the audit INSERT itself raises (e.g.,
    # a future schema constraint), the error is swallowed and the downgrade
    # still commits -- audit-write best-effort is a deliberate codebase-wide
    # convention. The transaction here protects against process crashes
    # between SQL statements, NOT against logger-internal failures.
    #
    # IMPORTANT: do NOT `return` from inside `User.transaction` -- in Rails
    # 7.1+ that triggers a deprecation warning and rolls back. Use guards
    # OUTSIDE the transaction for early-exit, and the transaction for the
    # commit-or-rollback work.
    #
    # Notification dispatch happens AFTER the transaction commits -- if the
    # downgrade rolls back, we must not send a "your trial ended" email to a
    # user who is still on Pro. Notification failures (Notification.create!
    # raising, mailer deliver_later raising) are rescued inside
    # notify_user_of_downgrade so they never roll back the downgrade.
    locked_and_eligible = false
    User.transaction do
      user.lock!
      eligible = user.trial_ends_at.present? &&
                 user.trial_ends_at <= Time.current &&
                 user.pro? &&
                 !user.billing_subscriptions.active_for_entitlements.exists?

      if eligible
        # Downgrading plan_tier fires the existing after_commit :enforce_plan_limits!
        # callback, which runs Pricing::PlanEnforcer and blocks any orgs that
        # exceed the free-tier ownership limit.
        user.update!(plan_tier: :free)

        user.owned_organizations.find_each do |org|
          Audit::Logger.log(
            action: "trial_expired",
            actor: user,
            organization: org,
            metadata: { trial_ends_at: user.trial_ends_at }
          )
        end

        locked_and_eligible = true
      end
    end

    notify_user_of_downgrade(user) if locked_and_eligible

    locked_and_eligible
  rescue => e
    Rails.logger.error("TrialExpirationJob: failed for user #{user.id}: #{e.class} #{e.message}")
    # TODO: when Sentry/Honeybadger is added, capture here:
    # Sentry.capture_exception(e, tags: { job: self.class.name, user_id: user.id }) if defined?(Sentry)
    false
  end

  # Fires the in-app notification + email AFTER the downgrade has committed.
  # Gated on the user's `notify_billing_changes?` preference, which is itself
  # gated on `email_notifications_enabled?` (see User#notify_billing_changes?).
  # Failures here are swallowed so a flaky mailer/notification write never
  # rolls back or re-raises from the already-committed downgrade path.
  def notify_user_of_downgrade(user)
    return unless user.notify_billing_changes?

    Notification.create!(
      user: user,
      notification_type: "trial_expired",
      title: "Trial ended — downgraded to Free",
      message: "Your 14-day Pro trial ended on #{user.trial_ends_at.strftime("%B %d, %Y")}. Pro features are now locked. Upgrade any time from the pricing page."
    )

    TrialMailer.expired(user: user).deliver_later
  rescue => e
    Rails.logger.error("TrialExpirationJob: notify_user_of_downgrade failed for user #{user.id}: #{e.class} #{e.message}")
  end
end
