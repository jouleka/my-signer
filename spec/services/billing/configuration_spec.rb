require "rails_helper"

RSpec.describe Billing::Configuration do
  around do |example|
    original = ENV.to_hash.slice(
      "BILLING_PROVIDER",
      "PADDLE_ENV",
      "PADDLE_CLIENT_SIDE_TOKEN",
      "PADDLE_API_KEY",
      "PADDLE_WEBHOOK_SECRET",
      "PADDLE_PRO_MONTHLY_PRICE_ID",
      "PADDLE_PRO_YEARLY_PRICE_ID",
      "PADDLE_TEAM_MONTHLY_PRICE_ID",
      "PADDLE_TEAM_YEARLY_PRICE_ID"
    )

    original.keys.each { |key| ENV.delete(key) }
    example.run
  ensure
    original.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  it "defaults the billing provider to Paddle" do
    expect(described_class.provider).to eq("paddle")
    expect(described_class.provider_name).to eq("Paddle")
  end

  it "reports self-serve checkout as unavailable until Paddle credentials are present" do
    expect(described_class.self_serve_checkout_available?).to be(false)
  end

  it "treats environment-prefixed Paddle credentials as required" do
    ENV["PADDLE_ENV"] = "sandbox"
    ENV["PADDLE_CLIENT_SIDE_TOKEN"] = "test_123456789012345678901234567"
    ENV["PADDLE_API_KEY"] = "pdl_sdbx_apikey_123"
    ENV["PADDLE_PRO_MONTHLY_PRICE_ID"] = "pri_monthly"
    ENV["PADDLE_PRO_YEARLY_PRICE_ID"] = "pri_yearly"
    ENV["PADDLE_TEAM_MONTHLY_PRICE_ID"] = "pri_team_monthly"
    ENV["PADDLE_TEAM_YEARLY_PRICE_ID"] = "pri_team_yearly"

    expect(described_class.paddle_checkout_ready?).to be(true)
    expect(described_class.paddle_backend_ready?).to be(true)
    expect(described_class.self_serve_checkout_available?).to be(true)
  end

  it "rejects mismatched live credentials in sandbox mode" do
    ENV["PADDLE_ENV"] = "sandbox"
    ENV["PADDLE_CLIENT_SIDE_TOKEN"] = "live_123456789012345678901234567"
    ENV["PADDLE_API_KEY"] = "pdl_live_apikey_123"
    ENV["PADDLE_PRO_MONTHLY_PRICE_ID"] = "pri_monthly"
    ENV["PADDLE_PRO_YEARLY_PRICE_ID"] = "pri_yearly"
    ENV["PADDLE_TEAM_MONTHLY_PRICE_ID"] = "pri_team_monthly"
    ENV["PADDLE_TEAM_YEARLY_PRICE_ID"] = "pri_team_yearly"

    expect(described_class.paddle_credentials_match_environment?).to be(false)
    expect(described_class.self_serve_checkout_available?).to be(false)
  end
end
