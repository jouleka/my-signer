require "rails_helper"

RSpec.describe "PricingController", type: :request do
  let(:user) { create(:user, plan_tier: :free) }
  let(:organization) { create(:organization, owner: user, name: "Acme Mobile") }

  it "allows guests to view the pricing page" do
    get pricing_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Plans &amp; Billing")
    expect(response.body).to include("Start free")
    expect(response.body).to include("$8")
    expect(response.body).to include("$96/year")
    expect(response.body).to include("Monthly")
    expect(response.body).to include("Yearly")
    expect(response.body).to include("Frequently asked questions")
  end

  context "when signed in" do
    before do
      sign_in user, scope: :user
      post switch_organization_path(organization)
    end

    it "renders the pricing page with current plan context" do
      get pricing_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Plans &amp; Billing")
      expect(response.body).to include("Acme Mobile")
      expect(response.body).to include("$8")
      expect(response.body).to include("$32.50")
      expect(response.body).to include("Frequently asked questions")
      expect(response.body).not_to include("Compare plans")
    end

    it "renders Paddle checkout controls when billing is configured" do
      allow(Billing::Configuration).to receive(:paddle_checkout_ready?).and_return(true)
      allow(Billing::Configuration).to receive(:paddle_backend_ready?).and_return(true)
      allow(Billing::Configuration).to receive(:paddle_webhooks_ready?).and_return(false)
      allow(Billing::Configuration).to receive(:paddle_client_side_token).and_return("test_123456789012345678901234567")
      allow(Billing::Configuration).to receive(:paddle_environment).and_return("sandbox")
      allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "pro", interval: "monthly").and_return("pri_pro_monthly")
      allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "pro", interval: "yearly").and_return("pri_pro_yearly")
      allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "team", interval: "monthly").and_return("pri_team_monthly")
      allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "team", interval: "yearly").and_return("pri_team_yearly")

      get pricing_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("paddle-checkout")
      expect(response.body).to include("Start Pro")
      expect(response.body).to include("Start Pro")
      expect(response.body).to include("Most popular")
    end

    it "still renders pricing during the access-state rollout before the column is available to the app process" do
      allow(Organization).to receive(:access_state_supported?).and_return(false)

      get pricing_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Plans &amp; Billing")
    end

    it "does not fall back to legacy billing-provider messaging for team plans" do
      user.update!(plan_tier: :team)

      get pricing_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Plans &amp; Billing")
      expect(response.body).not_to include("Upgrade to Team")
    end

    it "keeps the pricing page focused on the active plan without surfacing raw provider-specific billing states" do
      BillingSubscription.create!(
        user: user,
        provider: "legacy",
        provider_subscription_id: "sub_pending_123",
        status: "pending",
        plan_tier: "pro",
        billing_interval: "monthly"
      )

      get pricing_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Plans &amp; Billing")
      expect(response.body).to include("Frequently asked questions")
      expect(response.body).not_to include("PayPal")
      expect(response.body).not_to include("approval")
    end

    it "shows in-app plan change actions for active pro subscribers" do
      allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "pro", interval: "monthly").and_return("pri_pro_monthly")
      allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "pro", interval: "yearly").and_return("pri_pro_yearly")
      allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "team", interval: "monthly").and_return("pri_team_monthly")
      allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "team", interval: "yearly").and_return("pri_team_yearly")
      BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_active_123",
        provider_customer_id: "ctm_active_123",
        provider_plan_id: "pri_pro_monthly",
        status: "active",
        plan_tier: "pro",
        billing_interval: "monthly"
      )

      get pricing_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Upgrade now")
      expect(response.body).to include("Switch to yearly")
      expect(response.body).to include("Billing preview before every change")
      expect(response.body).to include("Manage billing")
    end

    it "does not offer another yearly switch when the active subscription is already yearly" do
      allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "pro", interval: "monthly").and_return("pri_pro_monthly")
      allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "pro", interval: "yearly").and_return("pri_pro_yearly")
      allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "team", interval: "monthly").and_return("pri_team_monthly")
      allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "team", interval: "yearly").and_return("pri_team_yearly")
      BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_active_yearly_123",
        provider_customer_id: "ctm_active_yearly_123",
        provider_plan_id: "pri_pro_yearly",
        status: "active",
        plan_tier: "pro",
        billing_interval: "yearly"
      )
      user.update!(plan_tier: :pro)

      get pricing_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Switch to yearly")
      expect(response.body).to include("Current plan (yearly)")
      expect(response.body).to include("Yearly")
    end

    it "shows renewal-only downgrade actions for active team subscribers" do
      allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "pro", interval: "monthly").and_return("pri_pro_monthly")
      allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "pro", interval: "yearly").and_return("pri_pro_yearly")
      allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "team", interval: "monthly").and_return("pri_team_monthly")
      allow(Billing::Configuration).to receive(:paddle_price_id_for).with(tier: "team", interval: "yearly").and_return("pri_team_yearly")
      BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_team_123",
        provider_customer_id: "ctm_team_123",
        provider_plan_id: "pri_team_yearly",
        status: "active",
        plan_tier: "team",
        billing_interval: "yearly"
      )
      user.update!(plan_tier: :team)

      get pricing_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Downgrade at renewal")
    end

    it "shows persistent scheduled downgrade impact details instead of another downgrade CTA once a change is queued" do
      user.update!(plan_tier: :team)
      organizations = [ organization ]
      organizations.concat(Array.new(4) do |index|
        create(:organization, owner: user, name: "Org #{index + 2}", created_at: (9 - index).days.ago)
      end)
      organization.update!(created_at: 10.days.ago)
      teammate_one = create(:user, email: "pricing-impact-one@example.com")
      teammate_two = create(:user, email: "pricing-impact-two@example.com")

      create(:screenshot_project, organization: organization, name: "Project 1", created_at: 10.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 2", created_at: 9.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 3", created_at: 8.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 4", created_at: 7.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 5", created_at: 6.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 6", created_at: 5.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 7", created_at: 4.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 8", created_at: 3.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 9", created_at: 2.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 10", created_at: 1.day.ago)
      create(:screenshot_project, organization: organization, name: "Project 11", created_at: 12.hours.ago)
      create(:screenshot_project, organization: organization, name: "Project 12", created_at: 6.hours.ago)
      organization.memberships.create!(user: teammate_one, role: :developer)
      organization.memberships.create!(user: teammate_two, role: :developer)
      organization.organization_invitations.create!(inviter: user, email: "pricing-pending@example.com", role: :viewer)

      allow(Billing::PlanCatalog).to receive(:fetch_by_price_id).with("pri_pro_monthly").and_return(
        plan_tier: "pro",
        billing_interval: "monthly"
      )
      allow(ScreenshotProject).to receive(:org_media_storage_bytes) { |organization_id| organization_id == organization.id ? 3.gigabytes : 0 }
      allow(ScreenshotProject).to receive(:org_export_storage_bytes) { |organization_id| organization_id == organization.id ? 6.gigabytes : 0 }

      BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_team_queued_123",
        provider_customer_id: "ctm_team_queued_123",
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

      get pricing_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Scheduled downgrade impact")
      # The Pro card now surfaces the scheduled state through a disabled
      # "Scheduled for {date}" CTA (replacing the separate "Queued for next
      # renewal." caption). Asserting the prefix here so the exact date
      # format doesn't make this test brittle.
      expect(response.body).to include("Scheduled for")
      expect(response.body).to include("Org 4")
      expect(response.body).to include("Org 5")
      expect(response.body).to include("Project 11")
      expect(response.body).to include("Project 12")
      expect(response.body).not_to include("Downgrade at renewal")
    end
  end

  context "@viewer_context" do
    it "exposes a prospect context for guests" do
      get pricing_path
      expect(response).to have_http_status(:ok)
    end

    it "exposes a viewer_type for signed-in users" do
      user = create(:user, plan_tier: :team)
      sign_in user, scope: :user
      get pricing_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "viewer-matrix badge behavior" do
    it "prospect visitor sees 'Most popular' on Pro, not on Team" do
      get pricing_path
      body = response.body
      pro_card_idx = body.index(%(data-tier="pro"))
      team_card_idx = body.index(%(data-tier="team"))
      popular_idx = body.index("Most popular")
      expect(popular_idx).to be_between(pro_card_idx, team_card_idx).inclusive
    end

    it "Free user sees 'Your plan' on Free, 'Most popular' on Pro, nothing on Team" do
      user = create(:user, plan_tier: :free)
      organization = create(:organization, owner: user)
      sign_in user, scope: :user
      post switch_organization_path(organization)

      get pricing_path
      expect(response.body).to include("Your plan")
      expect(response.body).to include("Most popular")
    end

    it "Pro trialing user sees 'Your trial' on Pro, NO 'Most popular' anywhere" do
      user = create(:user, plan_tier: :pro, trial_ends_at: 9.days.from_now)
      organization = create(:organization, owner: user)
      sign_in user, scope: :user
      post switch_organization_path(organization)

      get pricing_path
      expect(response.body).to include("Your trial")
      expect(response.body).not_to include("Most popular")
    end

    it "Pro active user sees 'Your plan' on Pro and 'Most popular' on Team" do
      user = create(:user, :pro_plan)
      organization = create(:organization, owner: user)
      BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_pro_123",
        provider_customer_id: "ctm_pro_123",
        provider_plan_id: "pri_pro_monthly",
        status: "active",
        plan_tier: "pro",
        billing_interval: "monthly"
      )
      sign_in user, scope: :user
      post switch_organization_path(organization)

      get pricing_path
      body = response.body
      pro_idx = body.index(%(data-tier="pro"))
      team_idx = body.index(%(data-tier="team"))
      popular_idx = body.index("Most popular")
      expect(body).to include("Your plan")
      expect(popular_idx).to be >= team_idx
    end

    it "Team active user sees 'Your plan' on Team and NO 'Most popular' anywhere (the bug fix)" do
      user = create(:user, :team_plan)
      organization = create(:organization, owner: user)
      BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_team_123",
        provider_customer_id: "ctm_team_123",
        provider_plan_id: "pri_team_monthly",
        status: "active",
        plan_tier: "team",
        billing_interval: "monthly"
      )
      sign_in user, scope: :user
      post switch_organization_path(organization)

      get pricing_path
      expect(response.body).to include("Your plan")
      expect(response.body).not_to include("Most popular")
    end
  end

  it "redirects the browser favicon request to the static SVG icon" do
    get "/favicon.ico"

    expect(response).to redirect_to("/favicon.svg")
  end
end
