require "rails_helper"

RSpec.describe TrialReminderJob do
  describe "#perform" do
    it "sends the halfway email to users with 7 days remaining" do
      user = create_user_with_trial(email: "day7@example.com", trial_ends_at: 7.days.from_now.middle_of_day)

      expect { described_class.new.perform }.to have_enqueued_mail(TrialMailer, :halfway).with(user: user)
    end

    it "sends the three_days_left email to users with 3 days remaining" do
      user = create_user_with_trial(email: "day3@example.com", trial_ends_at: 3.days.from_now.middle_of_day)

      expect { described_class.new.perform }.to have_enqueued_mail(TrialMailer, :three_days_left).with(user: user)
    end

    it "sends the last_day email to users with 1 day remaining" do
      user = create_user_with_trial(email: "day1@example.com", trial_ends_at: 1.day.from_now.middle_of_day)

      expect { described_class.new.perform }.to have_enqueued_mail(TrialMailer, :last_day).with(user: user)
    end

    it "does not send emails to users with 2 days remaining (not a milestone)" do
      create_user_with_trial(email: "day2@example.com", trial_ends_at: 2.days.from_now.middle_of_day)

      expect { described_class.new.perform }.not_to have_enqueued_mail(TrialMailer)
    end

    it "does not send emails to users who have an active billing subscription" do
      user = create_user_with_trial(email: "upgraded@example.com", trial_ends_at: 7.days.from_now.middle_of_day)
      BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_active_x",
        provider_customer_id: "ctm_active_x",
        provider_plan_id: "pri_pro_monthly",
        status: "active",
        plan_tier: "pro",
        billing_interval: "monthly"
      )

      expect { described_class.new.perform }.not_to have_enqueued_mail(TrialMailer)
    end

    it "does not send to users on free tier (trial already expired)" do
      User.create!(
        email: "free-user@example.com",
        password: "SecurePassword123!",
        confirmed_at: Time.current,
        plan_tier: :free
      )

      expect { described_class.new.perform }.not_to have_enqueued_mail(TrialMailer)
    end

    it "does not send the same milestone email twice on repeated runs (atomic dedup)" do
      # Regression guard: exercises the SQL check-and-set path in #send_reminder.
      # A typo in the jsonb operator or bind params would cause the second run
      # to re-enqueue the email silently.
      create_user_with_trial(email: "dedup@example.com", trial_ends_at: 7.days.from_now.middle_of_day)

      expect { described_class.new.perform }.to have_enqueued_mail(TrialMailer, :halfway).once
      expect { described_class.new.perform }.not_to have_enqueued_mail(TrialMailer, :halfway)
    end
  end

  def create_user_with_trial(email:, trial_ends_at:)
    user = User.create!(
      email: email,
      password: "SecurePassword123!",
      confirmed_at: Time.current,
      plan_tier: :free
    )
    user.update_columns(
      plan_tier: User.plan_tiers[:pro],
      trial_started_at: trial_ends_at - 14.days,
      trial_ends_at: trial_ends_at
    )
    user
  end
end
