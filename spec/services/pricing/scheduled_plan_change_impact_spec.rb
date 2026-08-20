require "rails_helper"

RSpec.describe Pricing::ScheduledPlanChangeImpact, type: :service do
  it "summarizes blocked organizations and kept-organization overages for a scheduled downgrade" do
    user = create(:user, :team_plan)
    organizations = Array.new(5) do |index|
      create(:organization, owner: user, name: "Org #{index + 1}", created_at: (10 - index).days.ago)
    end
    current_organization = organizations.first
    teammate_one = create(:user, email: "impact-one@example.com")
    teammate_two = create(:user, email: "impact-two@example.com")

    create(:screenshot_project, organization: current_organization, name: "Project 1", created_at: 10.days.ago)
    create(:screenshot_project, organization: current_organization, name: "Project 2", created_at: 9.days.ago)
    create(:screenshot_project, organization: current_organization, name: "Project 3", created_at: 8.days.ago)
    create(:screenshot_project, organization: current_organization, name: "Project 4", created_at: 7.days.ago)
    create(:screenshot_project, organization: current_organization, name: "Project 5", created_at: 6.days.ago)
    create(:screenshot_project, organization: current_organization, name: "Project 6", created_at: 5.days.ago)
    create(:screenshot_project, organization: current_organization, name: "Project 7", created_at: 4.days.ago)
    create(:screenshot_project, organization: current_organization, name: "Project 8", created_at: 3.days.ago)
    create(:screenshot_project, organization: current_organization, name: "Project 9", created_at: 2.days.ago)
    create(:screenshot_project, organization: current_organization, name: "Project 10", created_at: 1.day.ago)
    create(:screenshot_project, organization: current_organization, name: "Project 11", created_at: 12.hours.ago)
    create(:screenshot_project, organization: current_organization, name: "Project 12", created_at: 6.hours.ago)
    current_organization.memberships.create!(user: teammate_one, role: :developer)
    current_organization.memberships.create!(user: teammate_two, role: :developer)
    current_organization.organization_invitations.create!(inviter: user, email: "impact-pending@example.com", role: :viewer)

    allow(Billing::PlanCatalog).to receive(:fetch_by_price_id).with("pri_pro_monthly").and_return(
      plan_tier: "pro",
      billing_interval: "monthly"
    )
    allow(ScreenshotProject).to receive(:org_media_storage_bytes) { |organization_id| organization_id == current_organization.id ? 3.gigabytes : 0 }
    allow(ScreenshotProject).to receive(:org_export_storage_bytes) { |organization_id| organization_id == current_organization.id ? 6.gigabytes : 0 }

    subscription = BillingSubscription.new(
      user: user,
      provider: "paddle",
      provider_subscription_id: "sub_team_123",
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

    impact = described_class.new(user: user, subscription: subscription, organization: current_organization)

    expect(impact).to be_scheduled_downgrade
    expect(impact).to be_impactful
    expect(impact.blocked_organizations.map(&:name)).to eq([ "Org 4", "Org 5" ])
    expect(impact.current_organization_blocked?).to be(false)
    expect(impact.current_organization_impact).to be_present
    expect(impact.current_organization_impact.status.sections.map { |section| section[:key] }).to include(
      :seats,
      :screenshot_projects,
      :media_storage_bytes,
      :export_storage_bytes
    )
    expect(impact.current_organization_impact.status.overflow_screenshot_projects.map(&:name)).to eq([ "Project 11", "Project 12" ])
    expect(impact.to_h[:impactful]).to be(true)
  end

  it "returns a safe scheduled downgrade when the user already fits the target plan" do
    user = create(:user, :team_plan)
    organization = create(:organization, owner: user, name: "Org 1")

    allow(Billing::PlanCatalog).to receive(:fetch_by_price_id).with("pri_pro_monthly").and_return(
      plan_tier: "pro",
      billing_interval: "monthly"
    )

    subscription = BillingSubscription.new(
      user: user,
      provider: "paddle",
      provider_subscription_id: "sub_team_safe_123",
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

    impact = described_class.new(user: user, subscription: subscription, organization: organization)

    expect(impact).to be_scheduled_downgrade
    expect(impact).not_to be_impactful
    expect(impact).to be_safe
    expect(impact.blocked_organizations).to be_empty
    expect(impact.organization_impacts).to be_empty
  end

  it "ignores scheduled cancellations and same-tier yearly changes" do
    user = create(:user, :team_plan)
    organization = create(:organization, owner: user)

    cancel_subscription = BillingSubscription.new(
      user: user,
      provider: "paddle",
      provider_subscription_id: "sub_cancel_123",
      status: "active",
      plan_tier: "team",
      billing_interval: "monthly",
      provider_payload: {
        "scheduled_change" => {
          "action" => "cancel"
        }
      }
    )

    allow(Billing::PlanCatalog).to receive(:fetch_by_price_id).with("pri_pro_yearly").and_return(
      plan_tier: "pro",
      billing_interval: "yearly"
    )

    yearly_subscription = BillingSubscription.new(
      user: create(:user, :pro_plan),
      provider: "paddle",
      provider_subscription_id: "sub_yearly_123",
      status: "active",
      plan_tier: "pro",
      billing_interval: "monthly",
      provider_payload: {
        "scheduled_change" => {
          "effective_at" => 1.month.from_now.iso8601,
          "items" => [ { "price" => { "id" => "pri_pro_yearly" } } ]
        }
      }
    )

    expect(described_class.new(user: user, subscription: cancel_subscription, organization: organization)).not_to be_scheduled_downgrade
    expect(described_class.new(user: yearly_subscription.user, subscription: yearly_subscription, organization: organization)).not_to be_scheduled_downgrade
  end
end
