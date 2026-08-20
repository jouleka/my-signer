class TrialMailer < ApplicationMailer
  def halfway(user:)
    @user = user
    @days_remaining = 7
    @trial_ends_at = user.trial_ends_at
    mail(
      to: @user.email,
      subject: "You're halfway through your MySigner Pro trial — 7 days left"
    )
  end

  def three_days_left(user:)
    @user = user
    @days_remaining = 3
    @trial_ends_at = user.trial_ends_at
    mail(
      to: @user.email,
      subject: "3 days left on your MySigner Pro trial"
    )
  end

  def last_day(user:)
    @user = user
    @days_remaining = 1
    @trial_ends_at = user.trial_ends_at
    mail(
      to: @user.email,
      subject: "Last day of your MySigner Pro trial — don't lose access"
    )
  end

  def expired(user:)
    @user = user
    @trial_ended_at = user.trial_ends_at
    mail(
      to: @user.email,
      subject: "Your MySigner Pro trial has ended"
    )
  end
end
