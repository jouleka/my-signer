class BillingNotificationJob < ApplicationJob
  queue_as :default

  def perform(user_id:, event:, metadata: {})
    user = User.find_by(id: user_id)
    return unless user
    # Soft-deleted accounts are deactivated immediately per the privacy
    # policy. Continuing to send "your subscription cancelled" /
    # "payment past due" emails to a user who pressed "delete my account"
    # is both confusing and contradicts the deactivation promise.
    return if user.deleted?
    return unless user.notify_billing_changes?

    # These are user-level notifications with NULL resource_type/id, so the
    # unique indexes on `notifications` never trip and the old `rescue
    # RecordNotUnique` was dead. Use an atomic, stable cache claim keyed on the
    # event so a double-delivered job doesn't duplicate the notification/email.
    case event
    when "plan_changed"
      from_tier = metadata[:from] || metadata["from"]
      to_tier   = metadata[:to]   || metadata["to"]

      key = "billing:plan_changed:#{user.id}:#{from_tier}:#{to_tier}"
      return unless claim_dedup!(key: key)

      begin
        Notification.create!(
          user: user,
          notification_type: "plan_changed",
          title: "Plan changed to #{to_tier.to_s.capitalize}",
          message: "Your MySigner plan moved from #{from_tier.to_s.capitalize} to #{to_tier.to_s.capitalize}."
        )
      rescue StandardError
        release_dedup!(key: key)
        raise
      end

      BillingMailer.plan_changed(user: user, from_tier: from_tier, to_tier: to_tier).deliver_later
    when "payment_past_due"
      key = "billing:payment_past_due:#{user.id}"
      return unless claim_dedup!(key: key)

      begin
        Notification.create!(
          user: user,
          notification_type: "payment_past_due",
          title: "Payment past due",
          message: "We couldn't charge your card. Update billing to keep your current plan."
        )
      rescue StandardError
        release_dedup!(key: key)
        raise
      end

      BillingMailer.payment_past_due(user: user).deliver_later
    when "subscription_cancelled"
      key = "billing:subscription_cancelled:#{user.id}"
      return unless claim_dedup!(key: key)

      begin
        Notification.create!(
          user: user,
          notification_type: "subscription_cancelled",
          title: "Subscription cancelled",
          message: "Your subscription was cancelled. You'll keep access until the end of the billing period."
        )
      rescue StandardError
        release_dedup!(key: key)
        raise
      end

      BillingMailer.subscription_cancelled(user: user).deliver_later
    else
      Rails.logger.warn("BillingNotificationJob: unknown event #{event.inspect}")
    end
  end

  private

  DEDUP_TTL = 24.hours

  def claim_dedup!(key:)
    Rails.cache.write(key, true, unless_exist: true, expires_in: DEDUP_TTL)
  end

  def release_dedup!(key:)
    Rails.cache.delete(key)
  end
end
