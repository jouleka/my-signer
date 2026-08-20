class TrialReminderJob < ApplicationJob
  queue_as :default

  # Send reminders at day 7 (halfway), day 3 (approaching), day 1 (last day).
  # Each value is the number of days remaining when the email should arrive.
  REMINDER_DAYS = [ 7, 3, 1 ].freeze

  # Runs daily to send trial expiration reminder emails at specific milestones.
  # For each user whose trial ends in exactly N days (where N is in
  # REMINDER_DAYS), send the appropriate milestone email.
  #
  # Double-email prevention: the day-specific window ensures a user matches
  # each reminder bucket exactly once.
  def perform
    today = Date.current

    REMINDER_DAYS.each do |days_left|
      target_date = today + days_left.days
      trial_users_expiring_on(target_date).find_each do |user|
        send_reminder(user, days_left)
      end
    end
  end

  private

  def trial_users_expiring_on(date)
    User
      .where(trial_ends_at: date.beginning_of_day..date.end_of_day)
      .where(plan_tier: User.plan_tiers[:pro])
      .where.not(
        id: BillingSubscription.active_for_entitlements.select(:user_id)
      )
  end

  def send_reminder(user, days_left)
    # Deduplication: record the milestone on the user row inside an atomic
    # update. If the update returns 0 rows, another run already sent this
    # milestone -- skip. This prevents job retries/crashes from re-sending
    # the same reminder email on the same day.
    marker_key = days_left.to_s
    today_iso = Date.current.iso8601

    # Use a SQL update to atomically check-and-set: only update if the key
    # is absent or holds a different date. Both `marker_key` and `today_iso`
    # are passed as bind parameters -- never interpolated -- so this is safe
    # even if REMINDER_DAYS is ever expanded with values from less trusted
    # sources.
    update_sql = ActiveRecord::Base.sanitize_sql_array([
      "trial_reminders_sent = COALESCE(trial_reminders_sent, '{}'::jsonb) || jsonb_build_object(?, ?::text)",
      marker_key, today_iso
    ])
    rows = User.where(id: user.id)
      .where("COALESCE(trial_reminders_sent->>?, '') <> ?", marker_key, today_iso)
      .update_all(Arel.sql(update_sql))

    return if rows == 0  # Another run already sent this milestone today

    mailer_method = case days_left
    when 7 then :halfway
    when 3 then :three_days_left
    when 1 then :last_day
    end

    TrialMailer.public_send(mailer_method, user: user).deliver_later
  rescue => e
    Rails.logger.error("TrialReminderJob: failed for user #{user.id} (#{days_left}d): #{e.class} #{e.message}")
    # TODO: when Sentry/Honeybadger is added, capture here:
    # Sentry.capture_exception(e, tags: { job: self.class.name, user_id: user.id, days_left: days_left }) if defined?(Sentry)
  end
end
