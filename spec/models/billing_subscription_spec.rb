require "rails_helper"

RSpec.describe BillingSubscription, type: :model do
  describe "scheduled change helpers" do
    it "extracts the scheduled price and effective time" do
      allow(Billing::PlanCatalog).to receive(:fetch_by_price_id).with("pri_pro_yearly").and_return(
        plan_tier: "pro",
        billing_interval: "yearly"
      )

      subscription = described_class.new(
        user: build(:user),
        provider: "paddle",
        provider_subscription_id: "sub_test_123",
        status: "active",
        plan_tier: "pro",
        billing_interval: "monthly",
        provider_payload: {
          "scheduled_change" => {
            "effective_at" => "2026-04-25T10:00:00Z",
            "items" => [ { "price" => { "id" => "pri_pro_yearly" } } ]
          }
        }
      )

      expect(subscription.scheduled_change_price_id).to eq("pri_pro_yearly")
      expect(subscription.scheduled_change_effective_at).to eq(Time.zone.parse("2026-04-25T10:00:00Z"))
      expect(subscription.scheduled_change_target_tier).to eq("pro")
      expect(subscription.scheduled_change_target_interval).to eq("yearly")
    end

    it "detects scheduled cancellations" do
      subscription = described_class.new(
        user: build(:user),
        provider: "paddle",
        provider_subscription_id: "sub_cancel_123",
        status: "active",
        plan_tier: "pro",
        billing_interval: "monthly",
        provider_payload: {
          "scheduled_change" => {
            "action" => "cancel"
          }
        }
      )

      expect(subscription).to be_scheduled_change_cancel
      expect(subscription).not_to be_scheduled_plan_change
      expect(subscription).not_to be_scheduled_downgrade
    end

    it "detects scheduled downgrades and matching targets" do
      allow(Billing::PlanCatalog).to receive(:fetch_by_price_id).with("pri_pro_monthly").and_return(
        plan_tier: "pro",
        billing_interval: "monthly"
      )

      subscription = described_class.new(
        user: build(:user),
        provider: "paddle",
        provider_subscription_id: "sub_downgrade_123",
        status: "active",
        plan_tier: "team",
        billing_interval: "monthly",
        provider_payload: {
          "scheduled_change" => {
            "effective_at" => "2026-04-25T10:00:00Z",
            "items" => [ { "price" => { "id" => "pri_pro_monthly" } } ]
          }
        }
      )

      expect(subscription).to be_scheduled_plan_change
      expect(subscription).to be_scheduled_downgrade
      expect(subscription).not_to be_scheduled_same_tier_interval_change
      expect(subscription.scheduled_change_matches?(tier: :pro, interval: :monthly)).to be(true)
    end

    it "treats same-tier billing cadence changes separately from downgrades" do
      allow(Billing::PlanCatalog).to receive(:fetch_by_price_id).with("pri_pro_yearly").and_return(
        plan_tier: "pro",
        billing_interval: "yearly"
      )

      subscription = described_class.new(
        user: build(:user),
        provider: "paddle",
        provider_subscription_id: "sub_interval_123",
        status: "active",
        plan_tier: "pro",
        billing_interval: "monthly",
        provider_payload: {
          "scheduled_change" => {
            "effective_at" => "2026-04-25T10:00:00Z",
            "items" => [ { "price" => { "id" => "pri_pro_yearly" } } ]
          }
        }
      )

      expect(subscription).to be_scheduled_plan_change
      expect(subscription).not_to be_scheduled_downgrade
      expect(subscription).to be_scheduled_same_tier_interval_change
    end

    it "suppresses plan-change helpers when the scheduled price is unknown" do
      allow(Billing::PlanCatalog).to receive(:fetch_by_price_id).with("pri_unknown").and_return(nil)

      subscription = described_class.new(
        user: build(:user),
        provider: "paddle",
        provider_subscription_id: "sub_unknown_123",
        status: "active",
        plan_tier: "team",
        billing_interval: "monthly",
        provider_payload: {
          "scheduled_change" => {
            "effective_at" => "2026-04-25T10:00:00Z",
            "items" => [ { "price" => { "id" => "pri_unknown" } } ]
          }
        }
      )

      expect(subscription.scheduled_change_target_tier).to be_nil
      expect(subscription.scheduled_change_target_interval).to be_nil
      expect(subscription).not_to be_scheduled_plan_change
      expect(subscription).not_to be_scheduled_downgrade
    end
  end

  describe ".log_schedule_cleared_audit" do
    let(:user) { create(:user, :team_plan) }

    it "creates a schedule_cleared AuditEvent for each owned organization with schedule_kind metadata" do
      org_a = create(:organization, owner: user)
      org_b = create(:organization, owner: user)

      expect {
        described_class.log_schedule_cleared_audit(user: user, schedule_kind: :downgrade)
      }.to change { AuditEvent.where(action: "schedule_cleared").count }.by(2)

      events = AuditEvent.where(action: "schedule_cleared").order(:organization_id)
      expect(events.map(&:organization_id)).to match_array([ org_a.id, org_b.id ])
      expect(events.map { |e| e.metadata["schedule_kind"] }.uniq).to eq([ "downgrade" ])
      expect(events.map(&:actor_id).uniq).to eq([ user.id ])
    end

    it "falls back to the first membership org when the user owns zero organizations" do
      host_user = create(:user, :team_plan)
      host_org = create(:organization, owner: host_user)
      invitee = create(:user)
      create(:membership, user: invitee, organization: host_org)

      expect {
        described_class.log_schedule_cleared_audit(user: invitee, schedule_kind: :cancel)
      }.to change { AuditEvent.where(action: "schedule_cleared").count }.by(1)

      event = AuditEvent.where(action: "schedule_cleared").last
      expect(event.organization_id).to eq(host_org.id)
      expect(event.actor_id).to eq(invitee.id)
      expect(event.metadata["schedule_kind"]).to eq("cancel")
    end

    it "logs a warning and skips when the user has no orgs at all" do
      expect(Rails.logger).to receive(:warn).with(/log_schedule_cleared_audit skipped/)
      expect {
        described_class.log_schedule_cleared_audit(user: user, schedule_kind: :cancel)
      }.not_to change { AuditEvent.where(action: "schedule_cleared").count }
    end
  end

  describe "#schedule_kind" do
    it "returns :cancel when the scheduled_change is a cancellation" do
      subscription = described_class.new(
        user: build(:user),
        provider: "paddle",
        provider_subscription_id: "sub_cancel_kind",
        status: "active",
        plan_tier: "team",
        billing_interval: "yearly",
        provider_payload: { "scheduled_change" => { "action" => "cancel", "effective_at" => "2026-06-01T00:00:00Z" } }
      )

      expect(subscription.schedule_kind).to eq(:cancel)
    end

    it "returns :downgrade when a plan-change schedule is pending" do
      allow(Billing::PlanCatalog).to receive(:fetch_by_price_id).with("pri_pro_yearly").and_return(
        plan_tier: "pro",
        billing_interval: "yearly"
      )

      subscription = described_class.new(
        user: build(:user),
        provider: "paddle",
        provider_subscription_id: "sub_downgrade_kind",
        status: "active",
        plan_tier: "team",
        billing_interval: "yearly",
        provider_payload: {
          "scheduled_change" => {
            "action" => "update",
            "items" => [ { "price" => { "id" => "pri_pro_yearly" } } ],
            "effective_at" => "2026-06-01T00:00:00Z"
          }
        }
      )

      expect(subscription.schedule_kind).to eq(:downgrade)
    end

    it "returns nil when no schedule is pending" do
      subscription = described_class.new(
        user: build(:user),
        provider: "paddle",
        provider_subscription_id: "sub_none",
        status: "active",
        plan_tier: "pro",
        billing_interval: "yearly",
        provider_payload: {}
      )

      expect(subscription.schedule_kind).to be_nil
    end
  end
end
