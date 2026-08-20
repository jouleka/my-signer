require "rails_helper"

RSpec.describe Billing::SubscriptionChangePreviewPresenter do
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

  it "normalizes Paddle preview amounts and timing" do
    current_subscription = BillingSubscription.new(
      plan_tier: "pro",
      billing_interval: "monthly",
      status: "active",
      current_period_ends_at: Time.zone.parse("2026-04-26 10:00:00 UTC")
    )
    policy = Billing::SubscriptionChangePolicy.new(
      current_subscription: current_subscription,
      target_tier: "pro",
      target_interval: "yearly"
    )

    preview = described_class.new(
      preview: {
        "immediate_transaction" => {
          "details" => { "totals" => { "total" => "0", "currency_code" => "USD" } }
        },
        "next_transaction" => {
          "details" => { "totals" => { "total" => "9600", "currency_code" => "USD" } },
          "billing_period" => { "starts_at" => "2026-04-26T10:00:00Z" }
        },
        "recurring_transaction_details" => {
          "totals" => { "total" => "9600", "currency_code" => "USD" }
        },
        "update_summary" => {
          "result" => { "action" => "credit", "amount" => "1200", "currency_code" => "USD" }
        }
      },
      current_subscription: current_subscription,
      target_tier: "pro",
      target_interval: "yearly",
      policy: policy
    ).to_h

    expect(preview[:title]).to eq("Pro Yearly")
    expect(preview[:timing_label]).to eq("Applies now")
    expect(preview.dig(:due_today, :amount_cents)).to eq(0)
    expect(preview.dig(:next_charge, :formatted_amount)).to eq("$96")
    expect(preview.dig(:recurring_charge, :formatted_amount)).to eq("$96")
    expect(preview[:summary_line]).to eq("A prorated credit of $12 is expected as part of this change.")
  end

  it "uses the CURRENT plan's catalog price for Keep-plan (items_unchanged) transitions" do
    current_subscription = BillingSubscription.new(
      plan_tier: "team",
      billing_interval: "yearly",
      status: "active",
      current_period_ends_at: Time.zone.parse("2026-06-01 10:00:00 UTC"),
      provider_payload: {
        "scheduled_change" => {
          "action" => "update",
          "items" => [ { "price" => { "id" => "pri_pro_yearly" } } ],
          "effective_at" => "2026-06-01T10:00:00Z"
        }
      }
    )
    policy = Billing::SubscriptionChangePolicy.new(
      current_subscription: current_subscription,
      target_tier: "team",
      target_interval: "yearly"
    )

    preview = described_class.new(
      preview: {}, # Paddle returns empty body when there's no preview to compute
      current_subscription: current_subscription,
      target_tier: "team",
      target_interval: "yearly",
      policy: policy
    ).to_h

    # Recurring charge reflects the CURRENT plan (Team Yearly $390), not the
    # transition's nominal target — which equals current for Keep-plan anyway,
    # but the code path defends against future transitions where target may
    # differ from current while items_unchanged is true.
    expect(preview.dig(:next_charge, :amount_cents)).to eq(39_000)
    expect(preview.dig(:recurring_charge, :amount_cents)).to eq(39_000)
    expect(preview[:summary_line]).to include("No extra prorated credit or charge")
  end
end
