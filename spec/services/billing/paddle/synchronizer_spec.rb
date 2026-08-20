require "rails_helper"

RSpec.describe Billing::Paddle::Synchronizer do
  around do |example|
    original = ENV.to_hash.slice(
      "BILLING_PROVIDER",
      "PADDLE_PRO_MONTHLY_PRICE_ID",
      "PADDLE_PRO_YEARLY_PRICE_ID",
      "PADDLE_TEAM_MONTHLY_PRICE_ID",
      "PADDLE_TEAM_YEARLY_PRICE_ID"
    )

    ENV["BILLING_PROVIDER"] = "paddle"
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

  let(:user) { create(:user, :pro_plan) }
  let(:client) { instance_double(Billing::Paddle::Client) }

  it "treats a cadence-change payload with a yearly active item as yearly, not as a cancellation" do
    subscription = BillingSubscription.create!(
      user: user,
      provider: "paddle",
      provider_subscription_id: "sub_sync_123",
      provider_customer_id: "ctm_sync_123",
      provider_plan_id: "pri_pro_monthly",
      status: "active",
      plan_tier: "pro",
      billing_interval: "monthly",
      provider_payload: { "last_event_occurred_at" => 1.day.ago.iso8601 }
    )

    payload = {
      "id" => "sub_sync_123",
      "status" => "active",
      "customer_id" => "ctm_sync_123",
      "updated_at" => Time.current.iso8601,
      "items" => [ { "price" => { "id" => "pri_pro_yearly" } } ],
      "custom_data" => {
        "user_id" => user.id,
        "plan_tier" => "pro",
        "billing_interval" => "monthly"
      },
      "scheduled_change" => {
        "action" => "cancel",
        "effective_at" => 1.month.from_now.iso8601
      },
      "current_billing_period" => {
        "starts_at" => Time.current.iso8601,
        "ends_at" => 1.year.from_now.iso8601
      },
      "billing_cycle" => {
        "interval" => "year",
        "frequency" => 1
      }
    }

    synced = described_class.new(client: client).synchronize_subscription_payload!(
      payload,
      occurred_at: Time.current.iso8601,
      expected_user: user
    )

    expect(synced.id).to eq(subscription.id)
    expect(synced.plan_tier).to eq("pro")
    expect(synced.billing_interval).to eq("yearly")
    expect(synced.provider_plan_id).to eq("pri_pro_yearly")
    expect(synced.current_period_started_at).to be_present
    expect(synced.current_period_ends_at).to be_present
    expect(synced.cancel_at_period_end).to be(false)
    expect(synced.cancelled_at).to be_nil
  end

  it "marks a real end-of-period cancellation when the scheduled cancel matches the current period end" do
    payload = {
      "id" => "sub_cancel_123",
      "status" => "active",
      "customer_id" => "ctm_cancel_123",
      "items" => [ { "price" => { "id" => "pri_pro_monthly" } } ],
      "custom_data" => { "user_id" => user.id },
      "scheduled_change" => {
        "action" => "cancel",
        "effective_at" => "2026-04-25T10:00:00Z"
      },
      "current_billing_period" => {
        "starts_at" => "2026-03-25T10:00:00Z",
        "ends_at" => "2026-04-25T10:00:00Z"
      }
    }

    synced = described_class.new(client: client).synchronize_subscription_payload!(
      payload,
      occurred_at: Time.current.iso8601,
      expected_user: user
    )

    expect(synced.cancel_at_period_end).to be(true)
    expect(synced.cancelled_at).to eq(Time.zone.parse("2026-04-25T10:00:00Z"))
  end

  it "rejects payloads whose custom_data user does not match the expected user" do
    other_user = create(:user, :team_plan)
    payload = {
      "id" => "sub_wrong_owner_123",
      "status" => "active",
      "customer_id" => "ctm_wrong_owner_123",
      "items" => [ { "price" => { "id" => "pri_pro_monthly" } } ],
      "custom_data" => { "user_id" => other_user.id }
    }

    expect {
      described_class.new(client: client).synchronize_subscription_payload!(
        payload,
        occurred_at: Time.current.iso8601,
        expected_user: user
      )
    }.to raise_error(Billing::Paddle::Synchronizer::OwnershipMismatchError, "Checkout does not belong to the signed-in user.")
  end

  describe "webhook path ownership (expected_user: nil)" do
    it "quarantines a webhook whose custom_data.user_id contradicts the existing subscription owner (no rebind)" do
      attacker = create(:user, :team_plan)

      victim_subscription = BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_victim_001",
        provider_customer_id: "ctm_victim_001",
        provider_plan_id: "pri_pro_monthly",
        status: "trialing",
        plan_tier: "pro",
        billing_interval: "monthly",
        provider_payload: {}
      )

      # Attacker forges a webhook for the victim's subscription, claiming it as theirs.
      payload = {
        "id" => "sub_victim_001",
        "status" => "active",
        "customer_id" => "ctm_victim_001",
        "items" => [ { "price" => { "id" => "pri_team_yearly" } } ],
        "custom_data" => { "user_id" => attacker.id }
      }

      expect {
        described_class.new(client: client).synchronize_subscription_payload!(
          payload,
          occurred_at: Time.current.iso8601,
          expected_user: nil
        )
      }.to raise_error(Billing::Paddle::Synchronizer::QuarantinedOwnershipError)

      victim_subscription.reload
      expect(victim_subscription.user_id).to eq(user.id)
      expect(victim_subscription.plan_tier).to eq("pro")
      expect(victim_subscription.billing_interval).to eq("monthly")
      expect(victim_subscription.status).to eq("trialing")
    end

    it "binds a first-ever subscription to the server-side customer_id owner, ignoring a forged custom_data.user_id" do
      attacker = create(:user, :team_plan)

      # The victim's checkout already recorded this customer_id server-side.
      BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_victim_prior",
        provider_customer_id: "ctm_shared_002",
        provider_plan_id: "pri_pro_monthly",
        status: "active",
        plan_tier: "pro",
        billing_interval: "monthly",
        provider_payload: {}
      )

      # Attacker forges a brand-new subscription on the victim's customer_id.
      payload = {
        "id" => "sub_new_attacker",
        "status" => "active",
        "customer_id" => "ctm_shared_002",
        "items" => [ { "price" => { "id" => "pri_team_yearly" } } ],
        "custom_data" => { "user_id" => attacker.id }
      }

      expect {
        described_class.new(client: client).synchronize_subscription_payload!(
          payload,
          occurred_at: Time.current.iso8601,
          expected_user: nil
        )
      }.to raise_error(Billing::Paddle::Synchronizer::QuarantinedOwnershipError)

      expect(BillingSubscription.find_by(provider_subscription_id: "sub_new_attacker")).to be_nil
    end

    it "binds an existing subscription using its recorded owner when custom_data.user_id agrees" do
      BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_ok_003",
        provider_customer_id: "ctm_ok_003",
        provider_plan_id: "pri_pro_monthly",
        status: "trialing",
        plan_tier: "pro",
        billing_interval: "monthly",
        provider_payload: {}
      )

      payload = {
        "id" => "sub_ok_003",
        "status" => "active",
        "customer_id" => "ctm_ok_003",
        "items" => [ { "price" => { "id" => "pri_pro_monthly" } } ],
        "custom_data" => { "user_id" => user.id }
      }

      synced = described_class.new(client: client).synchronize_subscription_payload!(
        payload,
        occurred_at: Time.current.iso8601,
        expected_user: nil
      )

      expect(synced.user_id).to eq(user.id)
      expect(synced.status).to eq("active")
    end
  end
end
