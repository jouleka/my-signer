require "rails_helper"

# These specs lock in the critical security contract that an organization's
# entitlements always derive from the OWNER's plan_tier, not the current user's
# plan_tier. A free-tier user who is a member of a team-tier org MUST get the
# team's entitlements when operating within that org.
#
# This is the core of our team-seat model: when you pay for Team, everyone you
# invite benefits from your plan. Regressions here would either (a) cause paying
# customers to unexpectedly lose features for team members, or (b) allow members
# to operate with their personal (lower) plan's limits when they should have the
# owner's (higher) limits.
RSpec.describe "Plan entitlement inheritance for org members" do
  describe "when the owner is on Team and a Free user is a member" do
    let(:team_owner) do
      User.create!(
        email: "team-owner@example.com",
        password: "SecurePassword123!",
        confirmed_at: Time.current,
        plan_tier: User.plan_tiers[:team]
      )
    end

    let(:organization) { Organization.create!(name: "Team Org", owner: team_owner) }

    let(:free_member) do
      User.create!(
        email: "free-member@example.com",
        password: "SecurePassword123!",
        confirmed_at: Time.current,
        plan_tier: User.plan_tiers[:free]
      )
    end

    before do
      organization.memberships.create!(user: free_member, role: :developer)
    end

    it "returns Team entitlements for the org regardless of member's plan" do
      entitlements = organization.entitlements

      expect(entitlements.tier).to eq("team")
      expect(entitlements.max_seats_per_organization).to eq(10)
      expect(entitlements.max_tracked_keywords_per_app).to eq(200)
      expect(entitlements.max_ai_translations_per_month).to eq(500)
      expect(entitlements.max_analytics_history_days).to eq(365)
      expect(entitlements.store_upload_enabled?).to be true
      expect(entitlements.response_templates_enabled?).to be true
    end

    it "org.plan_tier reflects the owner's tier, not the member's" do
      expect(organization.plan_tier).to eq("team")
    end

    it "member's personal plan_tier remains free" do
      expect(free_member.reload.plan_tier).to eq("free")
    end

    it "member's personal entitlements (outside org context) remain Free" do
      expect(free_member.entitlements.tier).to eq("free")
      expect(free_member.entitlements.max_tracked_keywords_per_app).to eq(5)
    end
  end

  describe "when the owner is on Free and a Team user is a member" do
    let(:free_owner) do
      User.create!(
        email: "free-owner@example.com",
        password: "SecurePassword123!",
        confirmed_at: Time.current,
        plan_tier: User.plan_tiers[:free]
      )
    end

    let(:organization) { Organization.create!(name: "Free Org", owner: free_owner) }

    let(:team_member) do
      User.create!(
        email: "team-member@example.com",
        password: "SecurePassword123!",
        confirmed_at: Time.current,
        plan_tier: User.plan_tiers[:team]
      )
    end

    it "org entitlements reflect the owner's Free plan, not the member's Team plan" do
      # Free has max_seats=1, so we can't actually add the member via memberships.
      # The entitlement check itself resolves via owner regardless.
      expect(organization.entitlements.tier).to eq("free")
      expect(organization.entitlements.max_tracked_keywords_per_app).to eq(5)
      expect(organization.entitlements.store_upload_enabled?).to be false
    end
  end

  describe "Pricing::Entitlements.for_organization" do
    it "always delegates to the organization owner's plan_tier" do
      owner = User.create!(email: "owner@example.com", password: "SecurePassword123!",
                           confirmed_at: Time.current, plan_tier: User.plan_tiers[:pro])
      org = Organization.create!(name: "Pro Org", owner: owner)

      ents = Pricing::Entitlements.for_organization(org)
      expect(ents.tier).to eq("pro")
    end

    it "falls back to free when owner is nil" do
      org = Organization.new(name: "Orphan Org")
      allow(org).to receive(:owner).and_return(nil)

      ents = Pricing::Entitlements.for_organization(org)
      expect(ents.tier).to eq("free")
    end
  end
end
