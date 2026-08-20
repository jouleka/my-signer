require "rails_helper"

RSpec.describe Billing::SubscriptionChangePolicy do
  let(:user) { create(:user, :pro_plan) }

  around do |example|
    original = ENV.to_hash.slice(
      "PADDLE_PRO_MONTHLY_PRICE_ID",
      "PADDLE_PRO_YEARLY_PRICE_ID",
      "PADDLE_TEAM_MONTHLY_PRICE_ID",
      "PADDLE_TEAM_YEARLY_PRICE_ID"
    )

    ENV["PADDLE_PRO_MONTHLY_PRICE_ID"] = "pri_pro_monthly"
    ENV["PADDLE_PRO_YEARLY_PRICE_ID"] = "pri_pro_yearly"
    ENV["PADDLE_TEAM_MONTHLY_PRICE_ID"] = "pri_team_monthly"
    ENV["PADDLE_TEAM_YEARLY_PRICE_ID"] = "pri_team_yearly"

    example.run
  ensure
    original.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  def build_subscription(plan_tier:, billing_interval:)
    BillingSubscription.new(
      user: user,
      provider: "paddle",
      provider_subscription_id: "sub_test",
      status: "active",
      plan_tier: plan_tier,
      billing_interval: billing_interval
    )
  end

  it "supports immediate pro to team upgrades on the same interval" do
    policy = described_class.new(
      current_subscription: build_subscription(plan_tier: "pro", billing_interval: "monthly"),
      target_tier: "team",
      target_interval: "monthly"
    )

    expect(policy).to be_supported
    expect(policy.immediate_change?).to be(true)
    expect(policy.proration_billing_mode).to eq("prorated_immediately")
    expect(policy.label).to eq("Upgrade now")
  end

  it "supports monthly to yearly switches immediately without an immediate charge" do
    policy = described_class.new(
      current_subscription: build_subscription(plan_tier: "pro", billing_interval: "monthly"),
      target_tier: "pro",
      target_interval: "yearly"
    )

    expect(policy).to be_supported
    expect(policy.immediate_change?).to be(true)
    expect(policy.scheduled_change?).to be(false)
    expect(policy.proration_billing_mode).to eq("do_not_bill")
    expect(policy.label).to eq("Switch to yearly")
    expect(policy.message).to include("applies now")
  end

  it "supports team to pro downgrades at renewal on the same interval" do
    policy = described_class.new(
      current_subscription: build_subscription(plan_tier: "team", billing_interval: "monthly"),
      target_tier: "pro",
      target_interval: "monthly"
    )

    expect(policy).to be_supported
    expect(policy.scheduled_change?).to be(true)
    expect(policy.proration_billing_mode).to eq("prorated_next_billing_period")
    expect(policy.label).to eq("Downgrade at renewal")
    expect(policy.message).to include("downgrade credit")
  end

  it "supports pro monthly to team yearly upgrade immediately with proration" do
    policy = described_class.new(
      current_subscription: build_subscription(plan_tier: "pro", billing_interval: "monthly"),
      target_tier: "team",
      target_interval: "yearly"
    )

    expect(policy).to be_supported
    expect(policy.immediate_change?).to be(true)
    expect(policy.proration_billing_mode).to eq("prorated_immediately")
    expect(policy.label).to eq("Upgrade now")
    expect(policy.message).to include("Team yearly")
    expect(policy.target_price_id).to eq("pri_team_yearly")
  end

  describe "new policy fields" do
    it "exposes clear_scheduled_change? and items_unchanged? (default false) on every supported transition" do
      policy = described_class.new(
        current_subscription: build_subscription(plan_tier: "pro", billing_interval: "monthly"),
        target_tier: "team",
        target_interval: "monthly"
      )
      expect(policy.clear_scheduled_change?).to be(false)
      expect(policy.items_unchanged?).to be(false)
    end
  end

  describe "Keep current plan (target == current with schedule pending)" do
    def sub_with_cancel(plan_tier:, billing_interval:)
      BillingSubscription.new(
        user: user, provider: "paddle", provider_subscription_id: "sub_keep_cancel",
        status: "active", plan_tier: plan_tier, billing_interval: billing_interval,
        provider_payload: { "scheduled_change" => { "action" => "cancel", "effective_at" => 30.days.from_now.iso8601 } }
      )
    end

    def sub_with_downgrade(plan_tier: "team", billing_interval: "yearly", target_price_id: "pri_pro_yearly")
      BillingSubscription.new(
        user: user, provider: "paddle", provider_subscription_id: "sub_keep_downgrade",
        status: "active", plan_tier: plan_tier, billing_interval: billing_interval,
        provider_payload: {
          "scheduled_change" => {
            "action" => "update",
            "items" => [ { "price" => { "id" => target_price_id } } ],
            "effective_at" => 30.days.from_now.iso8601
          }
        }
      )
    end

    it "returns Keep Team plan when team-yearly user with scheduled pro-yearly downgrade clicks team-yearly" do
      policy = described_class.new(
        current_subscription: sub_with_downgrade,
        target_tier: "team",
        target_interval: "yearly"
      )

      expect(policy).to be_supported
      expect(policy.label).to eq("Keep Team plan")
      expect(policy.clear_scheduled_change?).to be(true)
      expect(policy.items_unchanged?).to be(true)
      expect(policy.immediate_change?).to be(true)
      expect(policy.scheduled_change?).to be(false)
      expect(policy.proration_billing_mode).to be_nil
    end

    it "returns Keep Pro plan when pro-yearly user with scheduled cancel clicks the same plan" do
      policy = described_class.new(
        current_subscription: sub_with_cancel(plan_tier: "pro", billing_interval: "yearly"),
        target_tier: "pro",
        target_interval: "yearly"
      )

      expect(policy).to be_supported
      expect(policy.label).to eq("Keep Pro plan")
      expect(policy.clear_scheduled_change?).to be(true)
      expect(policy.items_unchanged?).to be(true)
    end

    it "returns Keep Team plan when team-yearly user with scheduled cancel clicks the same plan" do
      # The most common churn scenario this feature is designed for: Team user
      # clicked Cancel in the Paddle portal, now wants to undo. The policy must
      # offer Keep-plan (NOT accidentally fire the Team→Pro branch).
      policy = described_class.new(
        current_subscription: sub_with_cancel(plan_tier: "team", billing_interval: "yearly"),
        target_tier: "team",
        target_interval: "yearly"
      )

      expect(policy).to be_supported
      expect(policy.label).to eq("Keep Team plan")
      expect(policy.clear_scheduled_change?).to be(true)
      expect(policy.items_unchanged?).to be(true)
      expect(policy.scheduled_change?).to be(false)
    end

    it "returns nil when target == current AND no schedule is pending (not a change)" do
      policy = described_class.new(
        current_subscription: build_subscription(plan_tier: "team", billing_interval: "yearly"),
        target_tier: "team",
        target_interval: "yearly"
      )
      expect(policy).not_to be_supported
    end
  end

  describe "Switch interval while a schedule is pending" do
    it "team-M with scheduled pro-M, target team-Y → switches to yearly AND clears schedule atomically" do
      sub = BillingSubscription.new(
        user: user, provider: "paddle", provider_subscription_id: "sub_sw_downgrade",
        status: "active", plan_tier: "team", billing_interval: "monthly",
        provider_payload: {
          "scheduled_change" => {
            "action" => "update",
            "items" => [ { "price" => { "id" => "pri_pro_monthly" } } ],
            "effective_at" => 30.days.from_now.iso8601
          }
        }
      )

      policy = described_class.new(current_subscription: sub, target_tier: "team", target_interval: "yearly")

      expect(policy).to be_supported
      expect(policy.label).to eq("Switch to yearly")
      expect(policy.proration_billing_mode).to eq("do_not_bill")
      expect(policy.clear_scheduled_change?).to be(true)
      expect(policy.items_unchanged?).to be(false)
      expect(policy.message).to include("Any scheduled change is cancelled")
    end

    it "pro-M with scheduled cancel, target pro-Y → switches to yearly AND clears the cancel" do
      sub = BillingSubscription.new(
        user: user, provider: "paddle", provider_subscription_id: "sub_sw_cancel",
        status: "active", plan_tier: "pro", billing_interval: "monthly",
        provider_payload: { "scheduled_change" => { "action" => "cancel", "effective_at" => 30.days.from_now.iso8601 } }
      )

      policy = described_class.new(current_subscription: sub, target_tier: "pro", target_interval: "yearly")

      expect(policy).to be_supported
      expect(policy.label).to eq("Switch to yearly")
      expect(policy.clear_scheduled_change?).to be(true)
    end
  end

  describe "Team→Pro over a pending cancel" do
    it "replaces the scheduled cancel with the downgrade (Paddle's single-slot atomic replacement)" do
      sub = BillingSubscription.new(
        user: user, provider: "paddle", provider_subscription_id: "sub_team_over_cancel",
        status: "active", plan_tier: "team", billing_interval: "yearly",
        provider_payload: { "scheduled_change" => { "action" => "cancel", "effective_at" => 30.days.from_now.iso8601 } }
      )

      policy = described_class.new(current_subscription: sub, target_tier: "pro", target_interval: "yearly")

      expect(policy).to be_supported
      expect(policy.label).to eq("Downgrade at renewal")
      expect(policy.proration_billing_mode).to eq("prorated_next_billing_period")
      expect(policy.clear_scheduled_change?).to be(false)
      expect(policy.message).to include("scheduled cancellation is replaced")
    end
  end

  describe "Trial safety invariant" do
    it "returns nil for trialing subscriptions regardless of pending schedule or target" do
      sub = BillingSubscription.new(
        user: user, provider: "paddle", provider_subscription_id: "sub_trial",
        status: "trialing", plan_tier: "pro", billing_interval: "yearly",
        provider_payload: { "scheduled_change" => { "action" => "update", "items" => [ { "price" => { "id" => "pri_team_yearly" } } ], "effective_at" => 30.days.from_now.iso8601 } }
      )

      policy = described_class.new(current_subscription: sub, target_tier: "team", target_interval: "yearly")

      expect(policy).not_to be_supported
    end
  end
end
