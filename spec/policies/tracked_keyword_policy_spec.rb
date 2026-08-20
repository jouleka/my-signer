require "rails_helper"
require "pundit/rspec"

RSpec.describe TrackedKeywordPolicy do
  subject { described_class }

  # Use :team_plan so the org can hold multiple memberships (Pro caps at 1 seat).
  let(:org_owner) { create(:user, :team_plan) }
  let(:org) { create(:organization, owner: org_owner) }
  let(:app) { create(:apple_app, organization: org) }
  let(:tk) { create(:tracked_keyword, apple_app: app) }

  let(:member) do
    user = create(:user)
    org.memberships.create!(user: user, role: :developer)
    user
  end

  let(:outsider) { create(:user, :pro_plan) }

  permissions :show?, :create?, :destroy? do
    it "grants owner access on Pro+" do
      expect(subject).to permit(org_owner, tk)
    end

    it "grants org member access on Pro+" do
      expect(subject).to permit(member, tk)
    end

    it "denies outsiders" do
      expect(subject).not_to permit(outsider, tk)
    end

    it "denies a nil user" do
      expect(subject).not_to permit(nil, tk)
    end
  end

  permissions :show?, :create? do
    it "denies when org is on Free plan (entitlement gate)" do
      org_owner.update!(plan_tier: :free)
      org.reset_entitlements_memo! if org.respond_to?(:reset_entitlements_memo!)
      expect(subject).not_to permit(org_owner, tk)
    end
  end

  permissions :destroy? do
    it "permits destroy even after downgrade to Free (cleanup path)" do
      org_owner.update!(plan_tier: :free)
      org.reset_entitlements_memo! if org.respond_to?(:reset_entitlements_memo!)
      expect(described_class).to permit(org_owner, tk)
    end
  end

  permissions :show?, :create?, :destroy? do
    it "denies when org is not accessible (suspended / plan-blocked)" do
      allow(org).to receive(:accessible?).and_return(false)
      allow(TrackedKeyword).to receive(:find).and_return(tk)
      allow(tk).to receive(:apple_app).and_return(app)
      allow(app).to receive(:organization).and_return(org)
      expect(described_class).not_to permit(org_owner, tk)
    end
  end

  describe "Scope" do
    it "returns only tracked keywords in user's orgs" do
      own_tk = tk
      other_owner = create(:user, :pro_plan)
      other_org = create(:organization, owner: other_owner)
      other_app = create(:apple_app, organization: other_org)
      other_tk = create(:tracked_keyword, apple_app: other_app)

      resolved = described_class::Scope.new(org_owner, TrackedKeyword.all).resolve
      expect(resolved).to include(own_tk)
      expect(resolved).not_to include(other_tk)
    end

    it "returns nothing for a nil user" do
      _tk = tk
      resolved = described_class::Scope.new(nil, TrackedKeyword.all).resolve
      expect(resolved).to be_empty
    end
  end
end
