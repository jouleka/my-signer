require "rails_helper"

RSpec.describe Pricing::PlanPayload, type: :service do
  it "builds a shared plan snapshot with usage and entitlement data" do
    owner = create(:user, :team_plan)
    organization = create(:organization, owner: owner)
    create(:organization, owner: owner, name: "Second Org")
    create(:user, email: "teammate@example.com").tap do |teammate|
      organization.memberships.create!(user: teammate, role: :developer)
    end
    organization.organization_invitations.create!(
      inviter: owner,
      email: "pending@example.com",
      role: :viewer
    )
    ScreenshotProject.create!(organization: organization, name: "Studio", platform: "both")
    organization.screenshot_uploads.create!(
      screenshot_project: organization.screenshot_projects.first,
      target: "google_play",
      status: "completed"
    )

    payload = described_class.for_organization(organization)

    expect(payload[:tier]).to eq("team")
    expect(payload[:next_tier]).to be_nil
    expect(payload[:entitlements][:features][:store_uploads]).to be(true)
    expect(payload[:usage][:owned_organizations]).to eq(2)
    expect(payload[:usage][:seats]).to eq(3)
    expect(payload[:usage][:active_memberships]).to eq(2)
    expect(payload[:usage][:pending_invitations]).to eq(1)
    expect(payload[:usage][:screenshot_projects]).to eq(1)
    expect(payload[:usage][:store_uploads_last_24_hours]).to eq(1)
    expect(payload[:scheduled_change_impact]).to be_nil
  end

  it "includes scheduled downgrade impact details for the current organization" do
    owner = create(:user, :team_plan)
    organization = create(:organization, owner: owner, name: "Primary Org", created_at: 10.days.ago)
    create(:organization, owner: owner, name: "Second Org", created_at: 9.days.ago)
    create(:organization, owner: owner, name: "Third Org", created_at: 8.days.ago)
    create(:organization, owner: owner, name: "Fourth Org", created_at: 7.days.ago)
    create(:organization, owner: owner, name: "Fifth Org", created_at: 6.days.ago)
    teammate_one = create(:user, email: "payload-impact-one@example.com")
    teammate_two = create(:user, email: "payload-impact-two@example.com")
    organization.memberships.create!(user: teammate_one, role: :developer)
    organization.memberships.create!(user: teammate_two, role: :developer)
    organization.organization_invitations.create!(inviter: owner, email: "payload-pending@example.com", role: :viewer)
    12.times do |index|
      create(:screenshot_project, organization: organization, name: "Project #{index + 1}", created_at: (12 - index).days.ago)
    end

    BillingSubscription.create!(
      user: owner,
      provider: "paddle",
      provider_subscription_id: "sub_payload_123",
      provider_customer_id: "ctm_payload_123",
      provider_plan_id: "pri_team_monthly",
      status: "active",
      plan_tier: "team",
      billing_interval: "monthly",
      provider_payload: {
        "scheduled_change" => {
          "effective_at" => 1.month.from_now.iso8601,
          "items" => [ { "price" => { "id" => "pri_pro_monthly" } } ]
        }
      }
    )

    allow(Billing::PlanCatalog).to receive(:fetch_by_price_id).with("pri_pro_monthly").and_return(
      plan_tier: "pro",
      billing_interval: "monthly"
    )
    allow(ScreenshotProject).to receive(:org_media_storage_bytes) { |organization_id| organization_id == organization.id ? 3.gigabytes : 0 }
    allow(ScreenshotProject).to receive(:org_export_storage_bytes) { |organization_id| organization_id == organization.id ? 6.gigabytes : 0 }

    payload = described_class.for_organization(organization)

    expect(payload[:scheduled_change_impact]).to include(
      target_tier: "pro",
      target_interval: "monthly",
      impactful: true
    )
    expect(payload[:scheduled_change_impact][:blocked_organizations].map { |org| org[:name] }).to eq([ "Fourth Org", "Fifth Org" ])
    expect(payload[:scheduled_change_impact][:organization_impacts].first[:overages][:frozen_project_ids].size).to eq(2)
  end

  describe ".capability_highlights" do
    it "returns 4 free-tier highlights with icon + label + description" do
      highlights = described_class.capability_highlights("free")
      expect(highlights).to be_an(Array)
      expect(highlights.size).to eq(4)
      expect(highlights.first).to be_a(Hash)
      expect(highlights.first.keys).to contain_exactly(:icon, :label, :description)
    end

    it "returns pro-tier highlights naming store uploads and AI translations" do
      highlights = described_class.capability_highlights("pro")
      labels = highlights.map { |h| h[:label] }
      expect(labels).to include("Store uploads")
      expect(labels.any? { |l| l.include?("AI translations") }).to be(true)
    end

    it "returns team-tier highlights naming SSO and audit log" do
      highlights = described_class.capability_highlights("team")
      labels = highlights.map { |h| h[:label] }
      expect(labels.any? { |l| l.include?("SSO") || l.include?("Audit log") }).to be(true)
      expect(labels.size).to eq(4)
    end

    it "raises ArgumentError for unknown tier" do
      expect { described_class.capability_highlights("enterprise") }.to raise_error(ArgumentError)
    end
  end

  describe ".usage_bars" do
    let(:owner) { create(:user, :pro_plan) }
    let(:organization) { create(:organization, owner: owner) }

    it "returns real usage bars for the organization's current tier" do
      bars = described_class.usage_bars(organization: organization, tier: "pro")
      expect(bars).to all(be_a(Pricing::UsageBar))
      expect(bars.size).to be_between(2, 3).inclusive
      expect(bars.none?(&:is_projection)).to be(true)
    end

    it "returns projection bars with multipliers for a higher tier" do
      bars = described_class.usage_bars(organization: organization, tier: "team")
      expect(bars).to all(be_a(Pricing::UsageBar))
      expect(bars).to all(be_is_projection)
      expect(bars.map(&:multiplier)).to all(be_a(Numeric))
      expect(bars.map(&:multiplier)).to all(be > 1)
    end

    it "returns an empty array for tiers below the organization's current tier" do
      bars = described_class.usage_bars(organization: organization, tier: "free")
      expect(bars).to eq([])
    end

    it "returns an empty array when organization is nil" do
      expect(described_class.usage_bars(organization: nil, tier: "pro")).to eq([])
    end
  end
end
