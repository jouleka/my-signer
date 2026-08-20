require "rails_helper"
require "pundit/rspec"

RSpec.describe OrganizationPolicy do
  subject { described_class }

  describe "#manage_byok?" do
    # BYOK is a Team-tier, admin/owner-only feature (mysigner-36). TWO gates
    # apply: the org must carry the BYOK entitlement (Team plan) AND the user
    # must be admin/owner. The role gate is intentionally tighter than
    # `manage_credentials?` because BYOK changes the cryptographic root for
    # every credential in the org — a wider blast radius than ordinary
    # credential edits.
    permissions :manage_byok? do
      it "DENIES the owner on the Free plan (no BYOK entitlement)" do
        owner = create(:user)
        org   = create(:organization, owner: owner)
        expect(subject).not_to permit(owner, org)
      end

      it "DENIES the owner on the Pro plan (no BYOK entitlement)" do
        owner = create(:user, :pro_plan)
        org   = create(:organization, owner: owner)
        expect(subject).not_to permit(owner, org)
      end

      it "permits the owner on the Team plan (entitlement present)" do
        owner = create(:user, :team_plan)
        org   = create(:organization, owner: owner)
        expect(subject).to permit(owner, org)
      end

      it "DENIES a Team-plan admin if the org is downgraded below the entitlement" do
        # Belt-and-suspenders: even an admin/owner loses BYOK the moment the
        # owner's plan drops below Team. Entitlements key off the owner's tier.
        owner = create(:user, :team_plan)
        org   = create(:organization, owner: owner)
        admin = create(:user)
        org.memberships.create!(user: admin, role: :admin)
        owner.update!(plan_tier: "pro")
        org.reset_entitlements_memo!
        expect(subject).not_to permit(admin, org)
      end

      it "permits an admin member on the Team plan (not just the owner)" do
        # WHY: the owner cases above cover the tier gate. This one nails down
        # that NON-owner admins also qualify once BOTH gates pass. Built under
        # the Team plan because that's the tier that carries the BYOK
        # entitlement (and Free's 1-seat limit would block the second
        # membership creation anyway).
        owner = create(:user, :team_plan)
        org   = create(:organization, owner: owner)
        admin = create(:user)
        org.memberships.create!(user: admin, role: :admin)
        expect(subject).to permit(admin, org)
      end

      it "DENIES developers (admin-only at the policy boundary)" do
        # WHY: BYOK changes the cryptographic root for every credential in
        # the org. That's a bigger blast radius than manage_credentials? —
        # we deliberately keep the policy gate tighter than the credentials
        # gate.
        owner = create(:user, :team_plan)
        org   = create(:organization, owner: owner)
        developer = create(:user)
        org.memberships.create!(user: developer, role: :developer)
        expect(subject).not_to permit(developer, org)
      end

      it "DENIES viewers" do
        owner = create(:user, :team_plan)
        org   = create(:organization, owner: owner)
        viewer = create(:user)
        org.memberships.create!(user: viewer, role: :viewer)
        expect(subject).not_to permit(viewer, org)
      end

      it "DENIES a non-member entirely" do
        owner = create(:user, :team_plan)
        org   = create(:organization, owner: owner)
        outsider = create(:user, :team_plan)
        expect(subject).not_to permit(outsider, org)
      end
    end
  end
end
