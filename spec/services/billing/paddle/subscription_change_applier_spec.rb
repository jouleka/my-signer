require "rails_helper"

RSpec.describe Billing::Paddle::SubscriptionChangeApplier do
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

  let(:client) { instance_double(Billing::Paddle::Client) }
  let(:synchronizer) { instance_double(Billing::Paddle::Synchronizer) }
  let(:user) { create(:user, :pro_plan) }

  it "synchronizes immediate upgrades right away" do
    current_subscription = BillingSubscription.create!(
      user: user,
      provider: "paddle",
      provider_subscription_id: "sub_123",
      provider_customer_id: "ctm_123",
      provider_plan_id: "pri_pro_monthly",
      status: "active",
      plan_tier: "pro",
      billing_interval: "monthly"
    )

    allow(client).to receive(:get_subscription).with("sub_123").and_return(
      "id" => "sub_123",
      "status" => "active",
      "items" => [ { "price" => { "id" => "pri_pro_monthly" }, "quantity" => 1 } ],
      "next_billed_at" => 5.days.from_now.iso8601
    )
    allow(client).to receive(:preview_subscription_update).and_return({ "update_summary" => {} })
    allow(client).to receive(:update_subscription).and_return(
      "id" => "sub_123",
      "status" => "active",
      "updated_at" => Time.current.iso8601,
      "customer_id" => "ctm_123",
      "items" => [ { "price" => { "id" => "pri_team_monthly" } } ],
      "custom_data" => { "user_id" => user.id },
      "current_billing_period" => {
        "starts_at" => Time.current.iso8601,
        "ends_at" => 1.month.from_now.iso8601
      }
    )
    synced_subscription = BillingSubscription.new(plan_tier: "team", billing_interval: "monthly", status: "active")
    allow(synchronizer).to receive(:synchronize_subscription_payload!).and_return(synced_subscription)

    result = described_class.new(
      user: user,
      current_subscription: current_subscription,
      target_tier: "team",
      target_interval: "monthly",
      client: client,
      synchronizer: synchronizer
    ).apply!

    expect(result.billing_subscription.plan_tier).to eq("team")
    expect(result.message).to eq("Team plan is active.")
    expect(synchronizer).to have_received(:synchronize_subscription_payload!)
  end

  it "persists scheduled downgrades without changing the local active plan immediately" do
    user.update!(plan_tier: :team)
    current_subscription = BillingSubscription.create!(
      user: user,
      provider: "paddle",
      provider_subscription_id: "sub_team_123",
      provider_customer_id: "ctm_team_123",
      provider_plan_id: "pri_team_monthly",
      status: "active",
      plan_tier: "team",
      billing_interval: "monthly",
      current_period_ends_at: 1.month.from_now
    )

    5.times { |n| create(:organization, owner: user, name: "Org #{n + 1}", created_at: (5 - n).days.ago) }

    allow(client).to receive(:get_subscription).with("sub_team_123").and_return(
      "id" => "sub_team_123",
      "status" => "active",
      "items" => [ { "price" => { "id" => "pri_team_monthly" }, "quantity" => 1 } ],
      "next_billed_at" => 1.month.from_now.iso8601
    )
    allow(client).to receive(:preview_subscription_update).with(
      "sub_team_123",
      items: [ { price_id: "pri_pro_monthly", quantity: 1 } ],
      proration_billing_mode: "prorated_next_billing_period",
      on_payment_failure: "prevent_change"
    ).and_return({ "update_summary" => {} })
    allow(client).to receive(:update_subscription).with(
      "sub_team_123",
      items: [ { price_id: "pri_pro_monthly", quantity: 1 } ],
      proration_billing_mode: "prorated_next_billing_period",
      on_payment_failure: "prevent_change"
    ).and_return(
      "id" => "sub_team_123",
      "status" => "active",
      "updated_at" => Time.current.iso8601,
      "customer_id" => "ctm_team_123",
      "items" => [ { "price" => { "id" => "pri_team_monthly" } } ],
      "scheduled_change" => {
        "effective_at" => 1.month.from_now.iso8601,
        "items" => [ { "price" => { "id" => "pri_pro_monthly" } } ]
      },
      "current_billing_period" => {
        "starts_at" => Time.current.iso8601,
        "ends_at" => 1.month.from_now.iso8601
      }
    )
    allow(synchronizer).to receive(:synchronize_subscription_payload!)

    result = described_class.new(
      user: user,
      current_subscription: current_subscription,
      target_tier: "pro",
      target_interval: "monthly",
      client: client,
      synchronizer: synchronizer
    ).apply!

    expect(current_subscription.reload.plan_tier).to eq("team")
    expect(current_subscription.scheduled_change_price_id).to eq("pri_pro_monthly")
    expect(result.message).to include("Pro Monthly is scheduled")
    expect(result.warning_messages.join(" ")).to include("will be blocked")
    expect(synchronizer).not_to have_received(:synchronize_subscription_payload!)
  end

  it "stores a provider event marker for queued downgrades so older webhooks cannot overwrite them" do
    user.update!(plan_tier: :team)
    current_subscription = BillingSubscription.create!(
      user: user,
      provider: "paddle",
      provider_subscription_id: "sub_stale_123",
      provider_customer_id: "ctm_stale_123",
      provider_plan_id: "pri_team_monthly",
      status: "active",
      plan_tier: "team",
      billing_interval: "monthly",
      current_period_ends_at: 1.month.from_now,
      provider_payload: { "last_event_occurred_at" => "2026-03-24T10:00:00Z" }
    )

    allow(client).to receive(:get_subscription).with("sub_stale_123").and_return(
      "id" => "sub_stale_123",
      "status" => "active",
      "items" => [ { "price" => { "id" => "pri_team_monthly" }, "quantity" => 1 } ],
      "next_billed_at" => 30.days.from_now.iso8601
    )
    allow(client).to receive(:preview_subscription_update).and_return({ "update_summary" => {} })
    allow(client).to receive(:update_subscription).and_return(
      "id" => "sub_stale_123",
      "status" => "active",
      "updated_at" => "2026-03-26T10:00:00Z",
      "customer_id" => "ctm_stale_123",
      "items" => [ { "price" => { "id" => "pri_team_monthly" } } ],
      "scheduled_change" => {
        "effective_at" => "2026-04-25T10:00:00Z",
        "items" => [ { "price" => { "id" => "pri_pro_monthly" } } ]
      },
      "current_billing_period" => {
        "starts_at" => "2026-03-25T10:00:00Z",
        "ends_at" => "2026-04-25T10:00:00Z"
      }
    )
    allow(synchronizer).to receive(:synchronize_subscription_payload!)

    described_class.new(
      user: user,
      current_subscription: current_subscription,
      target_tier: "pro",
      target_interval: "monthly",
      client: client,
      synchronizer: synchronizer
    ).apply!

    older_payload = {
      "id" => "sub_stale_123",
      "status" => "active",
      "customer_id" => "ctm_stale_123",
      "items" => [ { "price" => { "id" => "pri_team_monthly" } } ],
      "custom_data" => { "user_id" => user.id },
      "current_billing_period" => {
        "starts_at" => "2026-03-25T10:00:00Z",
        "ends_at" => "2026-04-25T10:00:00Z"
      }
    }

    Billing::Paddle::Synchronizer.new(client: client).synchronize_subscription_payload!(
      older_payload,
      occurred_at: "2026-03-25T10:00:00Z",
      expected_user: user
    )

    expect(current_subscription.reload.provider_payload["last_event_occurred_at"]).to eq("2026-03-26T10:00:00Z")
    expect(current_subscription.scheduled_change_price_id).to eq("pri_pro_monthly")
  end

  it "preserves extra recurring items when changing the base plan" do
    current_subscription = BillingSubscription.create!(
      user: user,
      provider: "paddle",
      provider_subscription_id: "sub_multi_item_123",
      provider_customer_id: "ctm_multi_item_123",
      provider_plan_id: "pri_pro_monthly",
      provider_product_id: "prod_base_plan",
      status: "active",
      plan_tier: "pro",
      billing_interval: "monthly"
    )

    live_subscription = {
      "id" => "sub_multi_item_123",
      "status" => "active",
      "next_billed_at" => 5.days.from_now.iso8601,
      "items" => [
        {
          "price" => { "id" => "pri_pro_monthly" },
          "product" => { "id" => "prod_base_plan" },
          "quantity" => 1
        },
        {
          "price" => { "id" => "pri_addon_monthly" },
          "product" => { "id" => "prod_addon" },
          "quantity" => 3
        }
      ]
    }
    allow(client).to receive(:get_subscription).with("sub_multi_item_123").and_return(live_subscription)
    allow(client).to receive(:preview_subscription_update).with(
      "sub_multi_item_123",
      items: [
        { price_id: "pri_team_monthly", quantity: 1 },
        { price_id: "pri_addon_monthly", quantity: 3 }
      ],
      proration_billing_mode: "prorated_immediately",
      on_payment_failure: "prevent_change"
    ).and_return({ "update_summary" => {} })
    allow(client).to receive(:update_subscription).with(
      "sub_multi_item_123",
      items: [
        { price_id: "pri_team_monthly", quantity: 1 },
        { price_id: "pri_addon_monthly", quantity: 3 }
      ],
      proration_billing_mode: "prorated_immediately",
      on_payment_failure: "prevent_change"
    ).and_return(
      "id" => "sub_multi_item_123",
      "status" => "active",
      "updated_at" => Time.current.iso8601,
      "customer_id" => "ctm_multi_item_123",
      "items" => [
        { "price" => { "id" => "pri_team_monthly" }, "product" => { "id" => "prod_base_plan" }, "quantity" => 1 },
        { "price" => { "id" => "pri_addon_monthly" }, "product" => { "id" => "prod_addon" }, "quantity" => 3 }
      ],
      "custom_data" => { "user_id" => user.id },
      "current_billing_period" => {
        "starts_at" => Time.current.iso8601,
        "ends_at" => 1.month.from_now.iso8601
      }
    )
    synced_subscription = BillingSubscription.new(plan_tier: "team", billing_interval: "monthly", status: "active")
    allow(synchronizer).to receive(:synchronize_subscription_payload!).and_return(synced_subscription)

    described_class.new(
      user: user,
      current_subscription: current_subscription,
      target_tier: "team",
      target_interval: "monthly",
      client: client,
      synchronizer: synchronizer
    ).apply!

    expect(synchronizer).to have_received(:synchronize_subscription_payload!)
  end

  it "synchronizes monthly to yearly switches right away when Paddle returns the yearly item as active" do
    current_subscription = BillingSubscription.create!(
      user: user,
      provider: "paddle",
      provider_subscription_id: "sub_yearly_123",
      provider_customer_id: "ctm_yearly_123",
      provider_plan_id: "pri_pro_monthly",
      status: "active",
      plan_tier: "pro",
      billing_interval: "monthly",
      current_period_ends_at: 1.month.from_now
    )

    allow(client).to receive(:get_subscription).with("sub_yearly_123").and_return(
      "id" => "sub_yearly_123",
      "status" => "active",
      "items" => [ { "price" => { "id" => "pri_pro_monthly" }, "quantity" => 1 } ],
      "next_billed_at" => 1.month.from_now.iso8601
    )
    allow(client).to receive(:preview_subscription_update).and_return({ "update_summary" => {} })
    allow(client).to receive(:update_subscription).and_return(
      "id" => "sub_yearly_123",
      "status" => "active",
      "updated_at" => Time.current.iso8601,
      "customer_id" => "ctm_yearly_123",
      "items" => [ { "price" => { "id" => "pri_pro_yearly" } } ],
      "custom_data" => { "user_id" => user.id },
      "current_billing_period" => {
        "starts_at" => Time.current.iso8601,
        "ends_at" => 1.year.from_now.iso8601
      },
      "billing_cycle" => {
        "frequency" => 1,
        "interval" => "year"
      }
    )
    synced_subscription = BillingSubscription.new(plan_tier: "pro", billing_interval: "yearly", status: "active")
    allow(synchronizer).to receive(:synchronize_subscription_payload!).and_return(synced_subscription)

    result = described_class.new(
      user: user,
      current_subscription: current_subscription,
      target_tier: "pro",
      target_interval: "yearly",
      client: client,
      synchronizer: synchronizer
    ).apply!

    expect(result.billing_subscription.billing_interval).to eq("yearly")
    expect(result.message).to eq("Pro Yearly is active. No immediate charge was made.")
    expect(synchronizer).to have_received(:synchronize_subscription_payload!)
  end

  it "clears a scheduled cancellation when an immediate yearly switch is applied" do
    current_subscription = BillingSubscription.create!(
      user: user,
      provider: "paddle",
      provider_subscription_id: "sub_resume_123",
      provider_customer_id: "ctm_resume_123",
      provider_plan_id: "pri_pro_monthly",
      status: "active",
      plan_tier: "pro",
      billing_interval: "monthly",
      current_period_ends_at: 1.month.from_now
    )

    allow(client).to receive(:get_subscription).with("sub_resume_123").and_return(
      "id" => "sub_resume_123",
      "status" => "active",
      "next_billed_at" => 1.month.from_now.iso8601,
      "items" => [
        {
          "price" => { "id" => "pri_pro_monthly" },
          "product" => { "id" => "prod_base_plan" },
          "quantity" => 1
        },
        {
          "price" => { "id" => "pri_addon_monthly" },
          "product" => { "id" => "prod_addon" },
          "quantity" => 2
        }
      ],
      "scheduled_change" => {
        "action" => "cancel",
        "effective_at" => 1.month.from_now.iso8601
      }
    )
    allow(client).to receive(:preview_subscription_update).with(
      "sub_resume_123",
      items: [
        { price_id: "pri_pro_yearly", quantity: 1 },
        { price_id: "pri_addon_monthly", quantity: 2 }
      ],
      proration_billing_mode: "do_not_bill",
      on_payment_failure: "prevent_change",
      scheduled_change: nil
    ).and_return({ "update_summary" => {} })
    allow(client).to receive(:update_subscription).with(
      "sub_resume_123",
      items: [
        { price_id: "pri_pro_yearly", quantity: 1 },
        { price_id: "pri_addon_monthly", quantity: 2 }
      ],
      proration_billing_mode: "do_not_bill",
      on_payment_failure: "prevent_change",
      scheduled_change: nil
    ).and_return(
      "id" => "sub_resume_123",
      "status" => "active",
      "updated_at" => Time.current.iso8601,
      "customer_id" => "ctm_resume_123",
      "items" => [ { "price" => { "id" => "pri_pro_yearly" } } ],
      "custom_data" => { "user_id" => user.id },
      "current_billing_period" => {
        "starts_at" => Time.current.iso8601,
        "ends_at" => 1.year.from_now.iso8601
      }
    )
    synced_subscription = BillingSubscription.new(plan_tier: "pro", billing_interval: "yearly", status: "active")
    allow(synchronizer).to receive(:synchronize_subscription_payload!).and_return(synced_subscription)

    result = described_class.new(
      user: user,
      current_subscription: current_subscription,
      target_tier: "pro",
      target_interval: "yearly",
      client: client,
      synchronizer: synchronizer
    ).apply!

    expect(result.message).to eq("Pro Yearly is active. No immediate charge was made. Scheduled cancellation was removed.")
    expect(synchronizer).to have_received(:synchronize_subscription_payload!)
  end

  it "blocks immediate changes when Paddle already has a scheduled pause" do
    current_subscription = BillingSubscription.create!(
      user: user,
      provider: "paddle",
      provider_subscription_id: "sub_pause_123",
      provider_customer_id: "ctm_pause_123",
      provider_plan_id: "pri_pro_monthly",
      status: "active",
      plan_tier: "pro",
      billing_interval: "monthly"
    )

    allow(client).to receive(:get_subscription).with("sub_pause_123").and_return(
      "id" => "sub_pause_123",
      "status" => "active",
      "next_billed_at" => 1.month.from_now.iso8601,
      "scheduled_change" => { "action" => "pause", "effective_at" => 1.month.from_now.iso8601 }
    )
    expect(client).not_to receive(:preview_subscription_update)
    expect(client).not_to receive(:update_subscription)

    expect {
      described_class.new(
        user: user,
        current_subscription: current_subscription,
        target_tier: "pro",
        target_interval: "yearly",
        client: client,
        synchronizer: synchronizer
      ).apply!
    }.to raise_error(described_class::Error, "Remove the scheduled pause in Paddle before changing this subscription.")
  end

  it "rejects live subscriptions that are past due" do
    current_subscription = BillingSubscription.create!(
      user: user,
      provider: "paddle",
      provider_subscription_id: "sub_past_due_123",
      provider_customer_id: "ctm_past_due_123",
      provider_plan_id: "pri_pro_monthly",
      status: "active",
      plan_tier: "pro",
      billing_interval: "monthly"
    )

    allow(client).to receive(:get_subscription).with("sub_past_due_123").and_return(
      "id" => "sub_past_due_123",
      "status" => "past_due",
      "next_billed_at" => 5.days.from_now.iso8601
    )
    expect(client).not_to receive(:preview_subscription_update)
    expect(client).not_to receive(:update_subscription)

    expect {
      described_class.new(
        user: user,
        current_subscription: current_subscription,
        target_tier: "team",
        target_interval: "monthly",
        client: client,
        synchronizer: synchronizer
      ).apply!
    }.to raise_error(described_class::Error, "This subscription is past due. Resolve billing in Paddle first.")
  end

  it "rejects changes inside Paddle's last-30-minutes renewal window" do
    current_subscription = BillingSubscription.create!(
      user: user,
      provider: "paddle",
      provider_subscription_id: "sub_locked_123",
      provider_customer_id: "ctm_locked_123",
      provider_plan_id: "pri_pro_monthly",
      status: "active",
      plan_tier: "pro",
      billing_interval: "monthly",
      current_period_ends_at: 2.days.from_now
    )

    allow(client).to receive(:get_subscription).with("sub_locked_123").and_return(
      "id" => "sub_locked_123",
      "status" => "active",
      "next_billed_at" => 20.minutes.from_now.iso8601
    )
    expect(client).not_to receive(:preview_subscription_update)
    expect(client).not_to receive(:update_subscription)

    expect {
      described_class.new(
        user: user,
        current_subscription: current_subscription,
        target_tier: "team",
        target_interval: "monthly",
        client: client,
        synchronizer: synchronizer
      ).apply!
    }.to raise_error(described_class::Error, "Subscription changes are temporarily unavailable in the last 30 minutes before renewal.")
  end

  # NOTE: the two tests that previously lived here asserted the blanket
  # `pending_plan_change_conflict?` and `scheduled_change_conflict?` raises.
  # Both guards were removed in the churn-handling change so the policy can
  # (a) handle Keep-plan undos and Switch-interval+clear atomically, and
  # (b) replace a scheduled cancel with a Pro downgrade via Paddle's single-slot
  # atomic replacement. The new behaviour is covered by:
  #  - Billing::SubscriptionChangePolicy spec (Keep-plan, Switch-interval-clear, Team→Pro-over-cancel)
  #  - Billing::Paddle::ScheduledChangesController spec (clearing pending schedules idempotently)

  describe "items_unchanged transitions (Keep-plan undo)" do
    it "calls Client#clear_scheduled_change instead of update_subscription, skips preview" do
      user.update!(plan_tier: :team)
      current_subscription = BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_keep_plan",
        provider_customer_id: "ctm_keep_plan",
        provider_plan_id: "pri_team_yearly",
        status: "active",
        plan_tier: "team",
        billing_interval: "yearly",
        provider_payload: {
          "scheduled_change" => {
            "action" => "update",
            "items" => [ { "price" => { "id" => "pri_pro_yearly" } } ],
            "effective_at" => 30.days.from_now.iso8601
          }
        }
      )

      allow(client).to receive(:get_subscription).with("sub_keep_plan").and_return(
        "id" => "sub_keep_plan",
        "status" => "active",
        "items" => [ { "price" => { "id" => "pri_team_yearly" } } ],
        "scheduled_change" => { "action" => "update" },
        "next_billed_at" => 30.days.from_now.iso8601
      )

      cleared_sub = {
        "id" => "sub_keep_plan",
        "status" => "active",
        "items" => [ { "price" => { "id" => "pri_team_yearly" } } ],
        "scheduled_change" => nil,
        "updated_at" => Time.current.iso8601
      }

      expect(client).to receive(:clear_scheduled_change).with("sub_keep_plan").and_return(cleared_sub)
      expect(client).not_to receive(:update_subscription)
      expect(client).not_to receive(:preview_subscription_update)
      expect(synchronizer).to receive(:synchronize_subscription_payload!).and_return(current_subscription)

      result = described_class.new(
        user: user,
        current_subscription: current_subscription,
        target_tier: "team",
        target_interval: "yearly",
        client: client,
        synchronizer: synchronizer
      ).apply!

      expect(result.preview).to eq({})
    end

    it "preview! returns empty paddle preview without hitting Paddle for a Keep-plan transition" do
      user.update!(plan_tier: :team)
      current_subscription = BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_keep_preview",
        provider_customer_id: "ctm_keep_preview",
        provider_plan_id: "pri_team_yearly",
        status: "active",
        plan_tier: "team",
        billing_interval: "yearly",
        provider_payload: {
          "scheduled_change" => {
            "action" => "update",
            "items" => [ { "price" => { "id" => "pri_pro_yearly" } } ],
            "effective_at" => 30.days.from_now.iso8601
          }
        }
      )

      allow(client).to receive(:get_subscription).with("sub_keep_preview").and_return(
        "id" => "sub_keep_preview",
        "status" => "active",
        "next_billed_at" => 30.days.from_now.iso8601
      )

      expect(client).not_to receive(:preview_subscription_update)
      expect(client).not_to receive(:update_subscription)
      expect(client).not_to receive(:clear_scheduled_change)

      result = described_class.new(
        user: user,
        current_subscription: current_subscription,
        target_tier: "team",
        target_interval: "yearly",
        client: client,
        synchronizer: synchronizer
      ).preview!

      expect(result.preview).to eq({})
      expect(result.message).to include("cancelled")
      expect(result.message).to include("Team Yearly")
    end
  end
end
