require "rails_helper"

RSpec.describe Pricing::ViewerContext do
  describe ".build" do
    it "returns a prospect context when user is nil" do
      ctx = described_class.build(user: nil, organization: nil, subscription: nil, plan_payload: nil)
      expect(ctx.signed_in).to be(false)
      expect(ctx.viewer_type).to eq(:prospect)
      expect(ctx.current_tier).to be_nil
      expect(ctx.recommended_tier).to eq("pro")
    end

    it "returns a :free viewer when user is on free plan with no subscription" do
      user = create(:user, plan_tier: :free)
      ctx = described_class.build(user: user, organization: nil, subscription: nil, plan_payload: nil)
      expect(ctx.signed_in).to be(true)
      expect(ctx.viewer_type).to eq(:free)
      expect(ctx.current_tier).to eq("free")
      expect(ctx.recommended_tier).to eq("pro")
    end

    it "returns a :pro_trialing viewer when user is in trial with no paid subscription" do
      user = create(:user, plan_tier: :pro, trial_ends_at: 9.days.from_now)
      ctx = described_class.build(user: user, organization: nil, subscription: nil, plan_payload: nil)
      expect(ctx.viewer_type).to eq(:pro_trialing)
      expect(ctx.current_tier).to eq("pro")
      expect(ctx.trial_days).to be_between(8, 9).inclusive
      expect(ctx.recommended_tier).to eq("team")
    end

    it "returns a :pro viewer when user has an active Pro subscription" do
      user = create(:user, :pro_plan)
      sub = BillingSubscription.new(plan_tier: "pro", status: "active")
      ctx = described_class.build(user: user, organization: nil, subscription: sub, plan_payload: nil)
      expect(ctx.viewer_type).to eq(:pro)
      expect(ctx.current_tier).to eq("pro")
      expect(ctx.recommended_tier).to eq("team")
    end

    it "returns a :team viewer when user has an active Team subscription" do
      user = create(:user, :team_plan)
      sub = BillingSubscription.new(plan_tier: "team", status: "active")
      ctx = described_class.build(user: user, organization: nil, subscription: sub, plan_payload: nil)
      expect(ctx.viewer_type).to eq(:team)
      expect(ctx.current_tier).to eq("team")
      expect(ctx.recommended_tier).to be_nil
    end
  end

  describe ".build — scheduled_change kind" do
    let(:user) { create(:user, :team_plan) }

    it "returns kind: :downgrade when the subscription has a scheduled plan change" do
      allow(Billing::Configuration).to receive(:paddle_price_id_for) do |tier:, interval:|
        "pri_#{tier}_#{interval}"
      end

      subscription = build(:billing_subscription, :with_scheduled_pro_downgrade, user: user)
      ctx = described_class.build(user: user, organization: nil, subscription: subscription, plan_payload: nil)

      expect(ctx.scheduled_change).to include(kind: :downgrade, from: "team", to: "pro")
      expect(ctx.scheduled_change[:effective_at]).to be_present
    end

    it "returns kind: :cancel when the subscription has a scheduled cancellation" do
      subscription = build(:billing_subscription, :team_yearly, :with_scheduled_cancel, user: user)
      ctx = described_class.build(user: user, organization: nil, subscription: subscription, plan_payload: nil)

      expect(ctx.scheduled_change).to include(kind: :cancel, from: "team", to: nil)
      expect(ctx.scheduled_change[:effective_at]).to be_present
    end

    it "returns nil for trialing users even if provider_payload contains a scheduled_change (invariant: trials don't trigger the policy)" do
      user = create(:user, plan_tier: :pro, trial_ends_at: 9.days.from_now)
      trialing_sub = BillingSubscription.new(
        user: user, provider: "paddle", provider_subscription_id: "sub_trial",
        plan_tier: "pro", billing_interval: "yearly", status: "trialing",
        provider_payload: { "scheduled_change" => { "action" => "update", "items" => [ { "price" => { "id" => "pri_team_yearly" } } ], "effective_at" => "2026-06-01T00:00:00Z" } }
      )
      # scheduled_plan_change? false on trial sub (Paddle doesn't allow it), scheduled_change_cancel? false
      allow(trialing_sub).to receive(:scheduled_plan_change?).and_return(false)

      ctx = described_class.build(user: user, organization: nil, subscription: trialing_sub, plan_payload: nil)

      expect(ctx.scheduled_change).to be_nil
    end

    it "returns nil when no schedule is present" do
      subscription = build(:billing_subscription, :team_yearly, user: user)
      ctx = described_class.build(user: user, organization: nil, subscription: subscription, plan_payload: nil)

      expect(ctx.scheduled_change).to be_nil
    end
  end

  describe "#show_most_popular_on?" do
    let(:build) { ->(viewer_type) { described_class.new(viewer_type: viewer_type) } }

    # Matrix test: [viewer_type, tier_being_asked, expected]
    [
      [ :prospect,      "free", false ],
      [ :prospect,      "pro",  true ],
      [ :prospect,      "team", false ],
      [ :free,          "free", false ],
      [ :free,          "pro",  true ],
      [ :free,          "team", false ],
      [ :pro_trialing,  "free", false ],
      [ :pro_trialing,  "pro",  false ],
      [ :pro_trialing,  "team", false ],
      [ :pro,           "free", false ],
      [ :pro,           "pro",  false ],
      [ :pro,           "team", true ],
      [ :team,          "free", false ],
      [ :team,          "pro",  false ],
      [ :team,          "team", false ]
    ].each do |viewer_type, tier, expected|
      it "returns #{expected} for viewer_type=#{viewer_type}, tier=#{tier}" do
        expect(build.call(viewer_type).show_most_popular_on?(tier)).to be(expected)
      end
    end
  end
end
