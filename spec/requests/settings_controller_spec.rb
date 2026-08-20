require "rails_helper"

RSpec.describe "SettingsController", type: :request do
  let(:user) { create(:user, :pro_plan) }

  before do
    sign_in user, scope: :user
  end

  it "shows blocked organizations in the membership list after a downgrade" do
    user.update!(plan_tier: :team)
    organizations = Array.new(5) do |index|
      create(:organization, owner: user, name: "Org #{index + 1}", created_at: (5 - index).days.ago)
    end

    user.update!(plan_tier: :pro)
    Pricing::PlanEnforcer.new(user).apply!

    get settings_path(tab: "organizations")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Blocked by plan")
    expect(response.body).to include(organizations.last.name)
    expect(response.body).to include(organizations.first.name)
    expect(response.body).to include("Pricing")
  end

  it "shows pending downgrade notices when the current billing subscription has a scheduled change" do
    allow(Billing::PlanCatalog).to receive(:fetch_by_price_id).with("pri_pro_monthly").and_return(
      plan_tier: "pro",
      billing_interval: "monthly"
    )

    BillingSubscription.create!(
      user: user,
      provider: "paddle",
      provider_subscription_id: "sub_team_123",
      provider_customer_id: "ctm_team_123",
      provider_plan_id: "pri_team_monthly",
      status: "active",
      plan_tier: "team",
      billing_interval: "monthly",
      current_period_ends_at: 1.month.from_now,
      provider_payload: {
        "scheduled_change" => {
          "effective_at" => 1.month.from_now.iso8601,
          "items" => [ { "price" => { "id" => "pri_pro_monthly" } } ]
        }
      }
    )
    user.update!(plan_tier: :team)

    get settings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pro Monthly starts on")
    expect(response.body).to include("Billing")
  end

  it "shows persistent scheduled downgrade impact details after the billing change is queued" do
    user.update!(plan_tier: :team)
    organizations = Array.new(5) do |index|
      create(:organization, owner: user, name: "Org #{index + 1}", created_at: (10 - index).days.ago)
    end
    current_organization = organizations.first
    teammate_one = create(:user, email: "settings-impact-one@example.com")
    teammate_two = create(:user, email: "settings-impact-two@example.com")

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
    current_organization.organization_invitations.create!(inviter: user, email: "settings-pending@example.com", role: :viewer)
    post switch_organization_path(current_organization)

    allow(Billing::PlanCatalog).to receive(:fetch_by_price_id).with("pri_pro_monthly").and_return(
      plan_tier: "pro",
      billing_interval: "monthly"
    )
    allow(ScreenshotProject).to receive(:org_media_storage_bytes) { |organization_id| organization_id == current_organization.id ? 3.gigabytes : 0 }
    allow(ScreenshotProject).to receive(:org_export_storage_bytes) { |organization_id| organization_id == current_organization.id ? 6.gigabytes : 0 }

    BillingSubscription.create!(
      user: user,
      provider: "paddle",
      provider_subscription_id: "sub_team_impact_123",
      provider_customer_id: "ctm_team_impact_123",
      provider_plan_id: "pri_team_monthly",
      status: "active",
      plan_tier: "team",
      billing_interval: "monthly",
      current_period_ends_at: 1.month.from_now,
      provider_payload: {
        "scheduled_change" => {
          "effective_at" => 1.month.from_now.iso8601,
          "items" => [ { "price" => { "id" => "pri_pro_monthly" } } ]
        }
      }
    )

    get settings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Scheduled downgrade impact")
    expect(response.body).to include("Pro Monthly starts on")
    expect(response.body).to include("Owned organizations")
    expect(response.body).to include("Org 4")
    expect(response.body).to include("Org 5")
    expect(response.body).to include("Current organization")
    expect(response.body).to include("Seats")
    expect(response.body).to include("Screenshot projects")
    expect(response.body).to include("Screenshot media storage")
    expect(response.body).to include("Screenshot export storage")
    expect(response.body).to include("Project 11")
    expect(response.body).to include("Project 12")
  end
end
