require "rails_helper"

RSpec.describe AuditEventPolicy do
  describe "Scope#resolve" do
    let(:team_owner) { User.create!(email: "team-owner@ex.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :team) }
    let(:team_admin_user) do
      u = User.create!(email: "team-admin@ex.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :free)
      u
    end
    let(:team_developer_user) do
      u = User.create!(email: "team-dev@ex.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :free)
      u
    end
    let(:pro_owner) { User.create!(email: "pro-owner@ex.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :pro) }
    let(:outsider) { User.create!(email: "outsider@ex.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :free) }

    let(:team_org) { Organization.create!(name: "Team Org", owner: team_owner) }
    let(:pro_org) { Organization.create!(name: "Pro Org", owner: pro_owner) }

    let!(:team_event)  { AuditEvent.create!(organization: team_org, action: "member_invited", created_at: Time.current) }
    let!(:pro_event)   { AuditEvent.create!(organization: pro_org,  action: "member_invited", created_at: Time.current) }

    before do
      team_org.memberships.create!(user: team_admin_user, role: :admin)
      team_org.memberships.create!(user: team_developer_user, role: :developer)
    end

    it "returns events for an owner of a Team-tier org" do
      scope = described_class::Scope.new(team_owner, AuditEvent).resolve
      expect(scope).to include(team_event)
      expect(scope).not_to include(pro_event)
    end

    it "returns events for an admin of a Team-tier org" do
      scope = described_class::Scope.new(team_admin_user, AuditEvent).resolve
      expect(scope).to include(team_event)
    end

    it "returns no events for a developer of a Team-tier org (role too low)" do
      scope = described_class::Scope.new(team_developer_user, AuditEvent).resolve
      expect(scope).not_to include(team_event)
      expect(scope).to be_empty
    end

    it "returns no events for an owner of a Pro-tier org (plan too low)" do
      scope = described_class::Scope.new(pro_owner, AuditEvent).resolve
      expect(scope).not_to include(pro_event)
      expect(scope).to be_empty
    end

    it "returns no events for a non-member of any org" do
      scope = described_class::Scope.new(outsider, AuditEvent).resolve
      expect(scope).to be_empty
    end

    it "returns no events for a nil user" do
      scope = described_class::Scope.new(nil, AuditEvent).resolve
      expect(scope).to be_empty
    end
  end
end
