require "rails_helper"

RSpec.describe OrganizationInvitation, type: :model do
  describe "seat limits" do
    it "blocks invitations when the free plan has no spare seats" do
      owner = create(:user)
      organization = create(:organization, owner: owner)

      invitation = organization.organization_invitations.build(
        inviter: owner,
        email: "invitee@example.com",
        role: :viewer
      )

      expect(invitation).not_to be_valid
      expect(invitation.errors[:base]).to include("Organization has reached the maximum of 1 seats on the Free plan")
    end

    it "counts active pending invitations toward the seat cap" do
      owner = create(:user, :pro_plan)
      organization = create(:organization, owner: owner)

      # Pro plan has 1 seat (owner only), so even the first invitation is blocked
      first_invitation = organization.organization_invitations.build(
        inviter: owner,
        email: "first@example.com",
        role: :viewer
      )

      expect(first_invitation).not_to be_valid
      expect(first_invitation.errors[:base]).to include("Organization has reached the maximum of 1 seats on the Pro plan")
    end

    it "rolls back acceptance if the organization no longer has capacity" do
      owner = create(:user, :team_plan)
      organization = create(:organization, owner: owner)
      invitation = organization.organization_invitations.create!(
        inviter: owner,
        email: "invitee@example.com",
        role: :viewer
      )

      owner.update!(plan_tier: :free)

      expect {
        invitation.accept!(create(:user, email: "invitee@example.com"))
      }.to raise_error(ActiveRecord::RecordInvalid, /maximum of 1 seats/)

      expect(invitation.reload.accepted_at).to be_nil
      expect(organization.memberships.count).to eq(1)
    end
  end

  describe "#accept!" do
    it "rejects acceptance for a different user email" do
      owner = create(:user, :team_plan)
      organization = create(:organization, owner: owner)
      invitation = organization.organization_invitations.create!(
        inviter: owner,
        email: "invitee@example.com",
        role: :viewer
      )

      expect {
        invitation.accept!(create(:user, email: "other@example.com"))
      }.to raise_error(RuntimeError, "This invitation is not for your account")

      expect(invitation.reload.accepted_at).to be_nil
      expect(organization.memberships.count).to eq(1)
    end

    it "does not let an existing admin consume someone else's invite" do
      owner = create(:user, :team_plan)
      organization = create(:organization, owner: owner)
      admin = create(:user, email: "admin@example.com")
      organization.memberships.create!(user: admin, role: :admin)
      invitation = organization.organization_invitations.create!(
        inviter: owner,
        email: "invitee@example.com",
        role: :viewer
      )

      expect {
        invitation.accept!(admin)
      }.to raise_error(RuntimeError, "This invitation is not for your account")

      expect(invitation.reload.accepted_at).to be_nil
      expect(organization.reload.seat_usage_count).to eq(3)
      expect(organization.memberships.where(user: admin).count).to eq(1)
    end

    it "rejects acceptance if the invite was cancelled after the caller loaded it" do
      owner = create(:user, :team_plan)
      organization = create(:organization, owner: owner)
      invitation = organization.organization_invitations.create!(
        inviter: owner,
        email: "invitee@example.com",
        role: :viewer
      )
      stale_invitation = described_class.active.find(invitation.id)

      invitation.cancel!

      expect {
        stale_invitation.accept!(create(:user, email: "invitee@example.com"))
      }.to raise_error(RuntimeError, "Invitation has been cancelled")

      expect(invitation.reload.accepted_at).to be_nil
      expect(invitation.cancelled_at).to be_present
      expect(organization.memberships.where.not(user: owner).count).to eq(0)
    end

    it "rejects acceptance if the invite was already accepted by another request" do
      owner = create(:user, :team_plan)
      organization = create(:organization, owner: owner)
      invitation = organization.organization_invitations.create!(
        inviter: owner,
        email: "invitee@example.com",
        role: :viewer
      )
      user = create(:user, email: "invitee@example.com")
      stale_invitation = described_class.active.find(invitation.id)

      invitation.accept!(user)

      expect {
        stale_invitation.accept!(user)
      }.to raise_error(RuntimeError, "Invitation has already been accepted")

      expect(invitation.reload.accepted_at).to be_present
      expect(organization.memberships.where(user: user).count).to eq(1)
    end
  end

  describe "#cancel!" do
    it "rejects cancellation after the invitation has already been accepted" do
      owner = create(:user, :team_plan)
      organization = create(:organization, owner: owner)
      invitation = organization.organization_invitations.create!(
        inviter: owner,
        email: "invitee@example.com",
        role: :viewer
      )

      invitation.accept!(create(:user, email: "invitee@example.com"))

      expect {
        invitation.cancel!
      }.to raise_error(RuntimeError, "Invitation has already been accepted")

      expect(invitation.reload.cancelled_at).to be_nil
    end
  end
end
