require "rails_helper"

RSpec.describe Pricing::UpgradePromptPayload, type: :service do
  describe ".build" do
    it "returns the shared upgrade prompt contract" do
      payload = described_class.build(
        current_plan: :free,
        required_plan: :pro,
        feature: "store uploads",
        message: "Store uploads require Pro.",
        suggestion: "Upgrade from Free to Pro to unlock store uploads.",
        source: "home#index:store-uploads-callout"
      )

      expect(payload).to eq(
        current_plan: "free",
        required_plan: "pro",
        feature: "store uploads",
        message: "Store uploads require Pro.",
        suggestion: "Upgrade from Free to Pro to unlock store uploads.",
        source: "home#index:store-uploads-callout"
      )
    end
  end

  describe ".for_quota_record" do
    it "builds a payload from a quota-exhausted record" do
      owner = create(:user, plan_tier: :free)
      create(:organization, owner: owner, name: "Existing Org")
      record = Organization.new(owner: owner, name: "One Too Many")

      expect(record).not_to be_valid

      expect(described_class.for_quota_record(record, source: "organizations#create")).to eq(
        current_plan: "free",
        required_plan: "pro",
        feature: "organization",
        message: "You can create a maximum of 1 organizations on the Free plan",
        suggestion: "Upgrade from Free to Pro to increase the organization limit.",
        source: "organizations#create"
      )
    end
  end
end
