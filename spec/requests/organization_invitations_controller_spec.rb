require "rails_helper"

RSpec.describe "Organization invitation resume flow", type: :request do
  let(:password) { "Password123!@#" }
  let(:owner) { create(:user, :team_plan, password: password) }
  let(:organization) { create(:organization, owner: owner) }
  let(:invitee) { create(:user, email: "invitee@example.com", password: password) }
  let(:other_user) { create(:user, email: "other@example.com", password: password) }
  let(:admin_user) { create(:user, email: "admin@example.com", password: password) }
  let!(:invitation) do
    organization.organization_invitations.create!(
      inviter: owner,
      email: invitee.email,
      role: :developer
    )
  end

  it "accepts the invitation after sign in for the matching email" do
    get accept_organization_invitation_path(token: invitation.token)

    expect(response).to redirect_to(new_user_session_path)

    expect {
      post user_session_path, params: {
        user: { email: invitee.email, password: password }
      }
    }.to change { organization.memberships.where(user: invitee).count }.by(1)

    expect(response).to redirect_to(organization_path(organization))
    expect(invitation.reload.accepted_at).to be_present
  end

  it "does not accept the invitation after sign in for a different email" do
    get accept_organization_invitation_path(token: invitation.token)

    expect(response).to redirect_to(new_user_session_path)

    expect {
      post user_session_path, params: {
        user: { email: other_user.email, password: password }
      }
    }.not_to change { organization.memberships.where(user: other_user).count }

    expect(invitation.reload.accepted_at).to be_nil
    expect(response).not_to redirect_to(organization_path(organization))
    expect(flash[:alert]).to eq("This invitation is not for your account")
  end

  it "does not let an existing admin consume someone else's invitation after sign in" do
    organization.memberships.create!(user: admin_user, role: :admin)

    get accept_organization_invitation_path(token: invitation.token)

    expect(response).to redirect_to(new_user_session_path)
    expect(organization.reload.seat_usage_count).to eq(3)

    expect {
      post user_session_path, params: {
        user: { email: admin_user.email, password: password }
      }
    }.not_to change { organization.memberships.where(user: admin_user).count }

    expect(invitation.reload.accepted_at).to be_nil
    expect(organization.reload.seat_usage_count).to eq(3)
    expect(response).not_to redirect_to(organization_path(organization))
    expect(flash[:alert]).to eq("This invitation is not for your account")
  end

  it "shows a seat-upgrade suggestion when invite creation hits the plan cap" do
    # Downgrade to Pro (1 seat = owner only) so any invite is blocked
    owner.update!(plan_tier: :pro)
    sign_in owner, scope: :user

    post organization_organization_invitations_path(organization), params: {
      organization_invitation: { email: "new@example.com", role: :viewer }
    }

    expect(response).to redirect_to(authenticated_root_path)
    expect(flash[:alert]).to include("maximum of 1 seats")
    expect(flash[:alert]).to include("Upgrade from Pro to Team to increase the seat limit.")
    expect(flash[:upgrade_prompt]["required_plan"]).to eq("team")
    expect(flash[:upgrade_prompt]["current_plan"]).to eq("pro")
  end

  it "renders the invite gate as blocked when pending invites consume the last seat" do
    # Downgrade to Pro (1 seat = owner only) so the gate is blocked
    # seat_usage_count = 2 (owner membership + pending invitation from let!)
    owner.update!(plan_tier: :pro)
    sign_in owner, scope: :user

    get organization_path(organization)

    expect(response).to have_http_status(:ok)
    expect(organization.reload.seat_usage_count).to eq(2)

    doc = Nokogiri::HTML(response.body)
    form = doc.at_css("form[action='#{organization_organization_invitations_path(organization)}']")
    prompt = JSON.parse(form["data-upgrade-gate-prompt-value"])

    expect(form["data-upgrade-gate-blocked-value"]).to eq("true")
    expect(form["data-upgrade-gate-close-nearest-dialog-value"]).to eq("true")
    expect(prompt).to include(
      "current_plan" => "pro",
      "required_plan" => "team",
      "feature" => "seat",
      "source" => "organizations#show:invite-member"
    )
  end

  it "suggests Team (not Pro) when a Free owner hits the seat cap" do
    # Free and Pro both cap seats at 1; Pro isn't a useful upgrade for more
    # members. Regression guard for an earlier bug where the prompt told
    # Free users to "Upgrade from Free to Pro to increase the seat limit",
    # even though Pro has the same 1-seat cap.
    owner.update!(plan_tier: :free)
    sign_in owner, scope: :user

    post organization_organization_invitations_path(organization), params: {
      organization_invitation: { email: "new@example.com", role: :viewer }
    }

    expect(response).to redirect_to(authenticated_root_path)
    expect(flash[:alert]).to include("maximum of 1 seats")
    expect(flash[:alert]).to include("Upgrade from Free to Team to increase the seat limit.")
    expect(flash[:upgrade_prompt]["required_plan"]).to eq("team")
    expect(flash[:upgrade_prompt]["current_plan"]).to eq("free")
  end

  it "does not let an accepted invitation be cancelled afterward" do
    sign_in owner, scope: :user
    invitation.accept!(invitee)

    delete organization_invitation_path(invitation)

    expect(response).to redirect_to(authenticated_root_path)
    expect(flash[:alert]).to eq("Invitation has already been accepted")
    expect(invitation.reload.cancelled_at).to be_nil
  end

  it "allows cancelling a pending invitation even after a downgrade leaves the organization over the seat cap" do
    organization.memberships.create!(user: admin_user, role: :admin)
    owner.update!(plan_tier: :free)
    sign_in owner, scope: :user

    expect(organization.reload.seat_usage_count).to eq(3)

    delete organization_invitation_path(invitation)

    expect(response).to redirect_to(authenticated_root_path)
    expect(flash[:notice]).to eq("Invitation cancelled")
    expect(invitation.reload.cancelled_at).to be_present
    expect(organization.reload.seat_usage_count).to eq(2)
  end
end
