require "rails_helper"

RSpec.describe User, type: :model do
  describe "reverse trial auto-start on create" do
    it "does NOT start trial when skip flag is set (default test behavior)" do
      # The rails_helper sets User.skip_reverse_trial_on_create = true before
      # each example, so this is the default test environment.
      user = User.create!(email: "no-trial@example.com", password: "SecurePassword123!", confirmed_at: Time.current)

      expect(user.plan_tier).to eq("free")
      expect(user.trial_ends_at).to be_nil
    end

    it "starts a 14-day pro trial when the skip flag is off (production behavior)" do
      User.with_reverse_trial do
        user = User.create!(email: "trial-start@example.com", password: "SecurePassword123!", confirmed_at: Time.current)

        expect(user.plan_tier).to eq("pro")
        expect(user.trial_started_at).to be_within(5.seconds).of(Time.current)
        expect(user.trial_ends_at).to be_within(5.seconds).of(14.days.from_now)
      end
    end

    it "does NOT override an explicitly-set paid plan tier on create" do
      User.with_reverse_trial do
        user = User.create!(
          email: "explicit-team@example.com",
          password: "SecurePassword123!",
          confirmed_at: Time.current,
          plan_tier: :team
        )

        # Trial callback respects explicit paid tiers (admin-provisioned).
        expect(user.plan_tier).to eq("team")
        expect(user.trial_ends_at).to be_nil
      end
    end

    # Pins the Fix 5.3 contract: `start_reverse_trial!` uses `update!` (not
    # `update_columns`), so the `after_commit :enforce_plan_limits!` callback
    # fires uniformly. For a freshly-created user with NO organizations the
    # PlanEnforcer is a no-op -- it must not raise, and the trial fields
    # must still be set correctly.
    it "fires the after_commit plan enforcer callback without error (no-op for fresh user)" do
      # Spy on PlanEnforcer to confirm the callback path actually runs.
      enforcer_double = instance_double(Pricing::PlanEnforcer, apply!: nil)
      expect(Pricing::PlanEnforcer).to receive(:new).at_least(:once).and_wrap_original do |orig, *args|
        # Wrap so the real enforcer still runs (it's a no-op for no-org users).
        orig.call(*args)
      end

      User.with_reverse_trial do
        user = User.create!(email: "callback-fires@example.com", password: "SecurePassword123!", confirmed_at: Time.current)

        expect(user.owned_organizations).to be_empty
        expect(user.plan_tier).to eq("pro")
        expect(user.trial_ends_at).to be_within(5.seconds).of(14.days.from_now)
      end
    end
  end

  describe "#on_active_trial?" do
    it "returns true for a user currently within trial window on pro" do
      user = User.create!(email: "active@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
      user.update_columns(
        plan_tier: User.plan_tiers[:pro],
        trial_started_at: 2.days.ago,
        trial_ends_at: 12.days.from_now
      )

      expect(user.on_active_trial?).to be true
    end

    it "returns false when trial window has passed" do
      user = User.create!(email: "past@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
      user.update_columns(
        plan_tier: User.plan_tiers[:pro],
        trial_started_at: 20.days.ago,
        trial_ends_at: 6.days.ago
      )

      expect(user.on_active_trial?).to be false
    end

    it "returns false when user has an active billing subscription" do
      user = User.create!(email: "subbed@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
      user.update_columns(
        plan_tier: User.plan_tiers[:pro],
        trial_started_at: 2.days.ago,
        trial_ends_at: 12.days.from_now
      )
      BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_1",
        provider_customer_id: "ctm_1",
        provider_plan_id: "pri_pro_monthly",
        status: "active",
        plan_tier: "pro",
        billing_interval: "monthly"
      )

      expect(user.reload.on_active_trial?).to be false
    end

    it "returns false for grandfathered users (no trial_ends_at)" do
      user = User.create!(email: "old@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :free)

      expect(user.on_active_trial?).to be false
    end
  end

  describe "#trial_days_remaining" do
    it "returns the integer days until trial_ends_at" do
      user = User.create!(email: "days@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
      user.update_columns(
        plan_tier: User.plan_tiers[:pro],
        trial_ends_at: 10.days.from_now
      )

      expect(user.trial_days_remaining).to eq(10)
    end

    it "returns 0 when not on a trial" do
      user = User.create!(email: "no-remain@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :free)

      expect(user.trial_days_remaining).to eq(0)
    end
  end

  describe "#trial_expired?" do
    it "returns true when trial has ended and no subscription" do
      user = User.create!(email: "expired@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
      user.update_columns(
        plan_tier: User.plan_tiers[:free],
        trial_started_at: 20.days.ago,
        trial_ends_at: 6.days.ago
      )

      expect(user.trial_expired?).to be true
    end

    it "returns false during active trial" do
      user = User.create!(email: "still-active@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
      user.update_columns(
        plan_tier: User.plan_tiers[:pro],
        trial_started_at: 1.day.ago,
        trial_ends_at: 13.days.from_now
      )

      expect(user.trial_expired?).to be false
    end
  end

  describe "BillingSubscription.recalculate_user_plan! clears trial" do
    it "clears trial fields when user upgrades to a paid subscription" do
      user = User.create!(email: "upgrader@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
      user.update_columns(
        plan_tier: User.plan_tiers[:pro],
        trial_started_at: 2.days.ago,
        trial_ends_at: 12.days.from_now
      )

      BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_upgrade",
        provider_customer_id: "ctm_upgrade",
        provider_plan_id: "pri_pro_monthly",
        status: "active",
        plan_tier: "pro",
        billing_interval: "monthly"
      )

      BillingSubscription.recalculate_user_plan!(user)

      expect(user.reload.trial_started_at).to be_nil
      expect(user.trial_ends_at).to be_nil
    end
  end
end
