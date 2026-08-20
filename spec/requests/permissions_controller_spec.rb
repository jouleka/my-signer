require "rails_helper"

RSpec.describe PermissionsController, type: :request do
  let(:owner) do
    User.create!(
      email: "team-owner@example.com",
      password: "SecurePassword123!",
      confirmed_at: Time.current,
      plan_tier: :team
    )
  end
  let(:organization) { Organization.create!(name: "Perms Org", owner: owner) }

  before { sign_in owner }

  describe "GET /organizations/:organization_id/permissions" do
    it "renders the role-permission matrix for a Team-tier org" do
      get organization_permissions_path(organization)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Permissions")
      expect(response.body).to include("What each role can do")
      expect(response.body).to include("Viewer")
      expect(response.body).to include("Developer")
      expect(response.body).to include("Admin")
      expect(response.body).to include("Owner")
    end

    it "includes capability rows from the permission matrix" do
      get organization_permissions_path(organization)

      expect(response.body).to include("View org data")
      expect(response.body).to include("Manage credentials")
      expect(response.body).to include("Delete organization")
    end

    context "when the org is on Pro plan" do
      before { owner.update!(plan_tier: :pro) }

      it "renders the Team-feature paywall instead of a generic denial" do
        get organization_permissions_path(organization)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Permissions Matrix")
        expect(response.body).to include("Team feature")
        expect(response.body).to include("Upgrade to Team")
      end
    end

    context "when the user is not a member of the org" do
      let(:outsider) do
        User.create!(email: "out@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :free)
      end
      before { sign_out owner; sign_in outsider }

      it "denies access" do
        get organization_permissions_path(organization)
        expect(response).not_to have_http_status(:ok)
      end
    end
  end
end
