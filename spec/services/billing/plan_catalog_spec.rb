require "rails_helper"

RSpec.describe Billing::PlanCatalog do
  it "returns the configured monthly and yearly offerings" do
    allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "pro", interval: "monthly").and_return("pri_pro_monthly")
    allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "pro", interval: "yearly").and_return("pri_pro_yearly")
    allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "team", interval: "monthly").and_return("pri_team_monthly")
    allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "team", interval: "yearly").and_return("pri_team_yearly")

    offerings = described_class.offerings

    expect(offerings.dig("pro", "monthly", :price)).to eq(BigDecimal("12.00"))
    expect(offerings.dig("pro", "yearly", :price)).to eq(BigDecimal("96.00"))
    expect(offerings.dig("team", "monthly", :price)).to eq(BigDecimal("49.00"))
    expect(offerings.dig("team", "yearly", :price)).to eq(BigDecimal("390.00"))
    expect(offerings.dig("pro", "monthly", :price_id)).to eq("pri_pro_monthly")
  end

  it "returns the internal tier and interval for a plan" do
    allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "team", interval: "yearly").and_return("pri_team_yearly")
    plan = described_class.fetch(tier: :team, interval: :yearly)

    expect(plan[:plan_tier]).to eq("team")
    expect(plan[:billing_interval]).to eq("yearly")
    expect(plan[:price_id]).to eq("pri_team_yearly")
  end

  it "looks up plans by Paddle price id" do
    allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "pro", interval: "monthly").and_return("pri_pro_monthly")
    allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "pro", interval: "yearly").and_return("pri_pro_yearly")
    allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "team", interval: "monthly").and_return("pri_team_monthly")
    allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "team", interval: "yearly").and_return("pri_team_yearly")

    plan = described_class.fetch_by_price_id("pri_team_monthly")

    expect(plan[:plan_tier]).to eq("team")
    expect(plan[:billing_interval]).to eq("monthly")
  end

  describe ".keyword_tracking_bullets" do
    it "returns Free tier bullets pulled from entitlements" do
      bullets = described_class.keyword_tracking_bullets("free")
      joined = bullets.join(" | ")

      expect(joined).to match(/5 tracked keywords/i)
      expect(joined).to match(/1 country/i)
      expect(joined).to match(/weekly refresh/i)
      expect(joined).to match(/7-day rank history/i)
      expect(joined).not_to match(/popularity/i)
      expect(joined).not_to match(/alerts/i)
      expect(joined).not_to match(/priority/i)
    end

    it "returns Pro tier bullets with Apple Ads popularity and 90-day history" do
      bullets = described_class.keyword_tracking_bullets("pro")
      joined = bullets.join(" | ")

      expect(joined).to match(/50 tracked keywords/i)
      expect(joined).to match(/3 countries/i)
      expect(joined).to match(/daily refresh/i)
      expect(joined).to match(/90-day rank history/i)
      expect(joined).to match(/apple search ads/i)
      expect(joined).to match(/popularity/i)
      expect(joined).not_to match(/alerts/i)
      expect(joined).not_to match(/priority/i)
    end

    it "returns Team tier bullets with alerts, priority queue, and 365-day history" do
      bullets = described_class.keyword_tracking_bullets("team")
      joined = bullets.join(" | ")

      expect(joined).to match(/200 tracked keywords/i)
      expect(joined).to match(/all app store countries/i)
      expect(joined).to match(/daily refresh/i)
      expect(joined).to match(/365-day rank history/i)
      expect(joined).to match(/apple search ads/i)
      expect(joined).to match(/rank change alerts/i)
      expect(joined).to match(/priority refresh queue/i)
    end

    it "accepts a symbol tier" do
      expect(described_class.keyword_tracking_bullets(:pro)).not_to be_empty
    end

    it "stays in sync with the entitlement catalog (no hardcoded keyword count)" do
      pro_ent = Pricing::Entitlements.new("pro")
      bullets = described_class.keyword_tracking_bullets("pro")

      expect(bullets.first).to include(pro_ent.max_tracked_keywords_per_app.to_s)
      expect(bullets.join(" | ")).to include("#{pro_ent.max_keyword_history_days}-day")
    end
  end
end
