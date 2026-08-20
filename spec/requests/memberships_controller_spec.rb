require "rails_helper"

RSpec.describe "MembershipsController", type: :request do
  let(:owner) { create(:user, :pro_plan) }
  # Eager (`let!`) so the org and its auto-created owner membership
  # (Organization#ensure_owner_membership!) exist BEFORE any `expect {}.not_to
  # change(Membership, :count)` block — otherwise lazily creating the org inside
  # the block counts the owner membership as the change under test.
  let!(:organization) { create(:organization, owner: owner) }

  before do
    sign_in owner, scope: :user
  end

  # Helper: a consented (active, outstanding) invitation for a target user.
  def invite!(user, role: :viewer)
    organization.organization_invitations.create!(
      email: user.email,
      role: role,
      inviter: owner
    )
  end

  it "shows upgrade guidance when the seat cap is reached" do
    # Pro plan has 1 seat, already filled by the owner's membership. The target
    # must have consented (invitation) to pass the consent gate, but creating an
    # invitation also enforces the seat cap — so we seed the invitation directly
    # (validate: false) to isolate and exercise the controller's membership-create
    # seat-cap backstop with consent already in place.
    extra = create(:user, email: "extra@example.com")
    organization.organization_invitations.new(
      email: extra.email,
      role: :viewer,
      inviter: owner,
      token: SecureRandom.hex(16),
      expires_at: 7.days.from_now
    ).save!(validate: false)

    expect {
      post organization_memberships_path(organization), params: {
        membership: { user_id: extra.id, role: :viewer }
      }
    }.not_to change(Membership, :count)

    expect(response).to redirect_to(organization_path(organization))
    expect(flash[:alert]).to include("maximum of 1 seats")
    expect(flash[:alert]).to include("Upgrade from Pro to Team to increase the seat limit.")
    expect(flash[:upgrade_prompt]["required_plan"]).to eq("team")
    expect(flash[:upgrade_prompt]["current_plan"]).to eq("pro")
  end

  it "allows removing a member even when the organization is already over the downgraded seat cap" do
    owner.update!(plan_tier: :team)
    member = create(:user, email: "member@example.com")
    membership = organization.memberships.create!(user: member, role: :developer)
    owner.update!(plan_tier: :free)

    expect(organization.reload.seat_usage_count).to eq(2)

    delete organization_membership_path(organization, membership)

    expect(response).to redirect_to(organization_path(organization))
    expect(flash[:notice]).to eq("Member removed")
    expect(organization.reload.seat_usage_count).to eq(1)
    expect(organization.memberships.where(user: member)).to be_empty
  end

  describe "#create consent gate (M-4)" do
    before { owner.update!(plan_tier: :team) } # >1 seat so consent, not the cap, is exercised

    it "adds a member who has an active (outstanding) invitation" do
      target = create(:user, email: "invited@example.com")
      invite!(target, role: :viewer)

      expect {
        post organization_memberships_path(organization), params: {
          membership: { user_id: target.id, role: :developer }
        }
      }.to change(Membership, :count).by(1)

      expect(response).to redirect_to(organization_path(organization))
      expect(flash[:notice]).to eq("Member added")
      expect(organization.memberships.find_by(user: target).role).to eq("developer")
    end

    it "adds a member who has an already-accepted invitation" do
      target = create(:user, email: "accepted@example.com")
      invite!(target, role: :viewer).update!(accepted_at: Time.current)

      expect {
        post organization_memberships_path(organization), params: {
          membership: { user_id: target.id, role: :viewer }
        }
      }.to change(Membership, :count).by(1)
    end

    it "refuses to add an arbitrary registered user with no invitation (consent bypass blocked)" do
      uninvited = create(:user, email: "stranger@example.com")

      expect {
        post organization_memberships_path(organization), params: {
          membership: { user_id: uninvited.id, role: :admin }
        }
      }.not_to change(Membership, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "ignores a cancelled invitation (no longer consenting)" do
      target = create(:user, email: "cancelled@example.com")
      invite!(target).update!(cancelled_at: Time.current)

      expect {
        post organization_memberships_path(organization), params: {
          membership: { user_id: target.id, role: :viewer }
        }
      }.not_to change(Membership, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "ignores an expired invitation (no longer consenting)" do
      target = create(:user, email: "expired@example.com")
      invite!(target).update!(expires_at: 1.day.ago)

      expect {
        post organization_memberships_path(organization), params: {
          membership: { user_id: target.id, role: :viewer }
        }
      }.not_to change(Membership, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "only honors invitations scoped to the current organization" do
      other_org = create(:organization, owner: owner)
      target = create(:user, email: "otherorg@example.com")
      # Invitation belongs to a DIFFERENT org; must not authorize add here.
      other_org.organization_invitations.create!(email: target.email, role: :viewer, inviter: owner)

      expect {
        post organization_memberships_path(organization), params: {
          membership: { user_id: target.id, role: :viewer }
        }
      }.not_to change(Membership, :count)

      expect(response).to have_http_status(:not_found)
    end

    # Enumeration resistance: a non-existent user id and an existing-but-uninvited
    # user id must be INDISTINGUISHABLE — both a plain 404. Split into two
    # single-request examples: chaining two POSTs in one example is fragile
    # because the first (which raises RecordNotFound -> 404) disturbs the
    # request-spec's Devise session for the second request.
    it "returns a uniform 404 for a non-existent user id (no enumeration signal)" do
      missing_id = User.maximum(:id).to_i + 100_000
      post organization_memberships_path(organization), params: {
        membership: { user_id: missing_id, role: :viewer }
      }
      expect(response).to have_http_status(:not_found)
    end

    it "returns the same uniform 404 for an existing-but-uninvited user id (no enumeration signal)" do
      uninvited = create(:user, email: "exists-uninvited@example.com")
      post organization_memberships_path(organization), params: {
        membership: { user_id: uninvited.id, role: :viewer }
      }
      expect(response).to have_http_status(:not_found)
    end

    it "returns a uniform 404 when user_id is omitted entirely" do
      post organization_memberships_path(organization), params: {
        membership: { role: :viewer }
      }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "#update (L-6)" do
    before { owner.update!(plan_tier: :team) }

    it "permits changing only the role" do
      member = create(:user, email: "rolechange@example.com")
      membership = organization.memberships.create!(user: member, role: :viewer)

      patch organization_membership_path(organization, membership), params: {
        membership: { role: :developer }
      }

      expect(response).to redirect_to(organization_path(organization))
      expect(membership.reload.role).to eq("developer")
      expect(membership.user_id).to eq(member.id)
    end

    it "never reassigns the membership to a different user_id (mass-assignment blocked)" do
      member = create(:user, email: "victim@example.com")
      attacker = create(:user, email: "attacker@example.com")
      membership = organization.memberships.create!(user: member, role: :viewer)

      patch organization_membership_path(organization, membership), params: {
        membership: { role: :developer, user_id: attacker.id }
      }

      # Role updated, but the membership still belongs to the original user.
      expect(membership.reload.role).to eq("developer")
      expect(membership.user_id).to eq(member.id)
    end
  end
end
