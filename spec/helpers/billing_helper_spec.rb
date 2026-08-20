require "rails_helper"

RSpec.describe BillingHelper, type: :helper do
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

  describe "#billing_plan_display" do
    it "shows yearly plans as monthly equivalents with savings details" do
      display = helper.billing_plan_display(tier: "team", interval: "yearly")

      expect(display[:amount]).to eq("$32.50")
      expect(display[:unit_label]).to eq("/mo")
      expect(display[:billing_note]).to eq("$390/year billed annually")
      expect(display[:savings_badge]).to eq("4 months free")
      expect(display[:savings_detail]).to eq("Save $198 vs monthly")
    end
  end

  describe "#billing_cancellation_summary" do
    it "describes the scheduled cancellation end date" do
      subscription = BillingSubscription.new(
        status: "active",
        plan_tier: "pro",
        billing_interval: "monthly",
        current_period_ends_at: Time.zone.parse("2026-04-26 10:00:00 UTC"),
        cancel_at_period_end: true,
        cancelled_at: Time.zone.parse("2026-04-26 10:00:00 UTC")
      )

      expect(helper.billing_cancellation_summary(subscription)).to include("Cancellation is already scheduled")
      expect(helper.billing_current_plan_summary(subscription)).to include("ends on")
    end
  end
end
