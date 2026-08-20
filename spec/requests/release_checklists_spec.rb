require "rails_helper"

RSpec.describe "ReleaseChecklists", type: :request do
  let(:user) { create(:user, :team_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) { create(:apple_app, organization: organization) }
  let!(:checklist) { create(:release_checklist, organization: organization, listable: apple_app) }
  # release_id param uses "apple_app_<id>" format per ReleasesController#find_release_app
  let(:release_id) { "apple_app_#{apple_app.id}" }

  before do
    sign_in user, scope: :user
  end

  describe "GET /organizations/:organization_id/releases/:release_id/release_checklists/:id" do
    it "shows the checklist" do
      get organization_release_release_checklist_path(organization, release_id, checklist), as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /organizations/:organization_id/releases/:release_id/release_checklists/:id" do
    it "updates the checklist" do
      patch organization_release_release_checklist_path(organization, release_id, checklist), params: {
        release_checklist: { version_string: "2.0.0", platform: "ios" }
      }
      expect(response).to redirect_to(organization_release_path(organization, release_id))
      expect(checklist.reload.version_string).to eq("2.0.0")
    end

    it "returns JSON response when requested" do
      patch organization_release_release_checklist_path(organization, release_id, checklist),
        params: { release_checklist: { version_string: "2.0.0" } },
        as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["status"]).to eq("updated")
      expect(data["completion"]).to be_a(Integer)
    end
  end

  describe "POST /organizations/:organization_id/releases/:release_id/release_checklists/:id/check_item" do
    it "checks an item and returns JSON" do
      post check_item_organization_release_release_checklist_path(organization, release_id, checklist),
        params: { key: "release_notes_written" },
        as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["status"]).to eq("checked")
      expect(data["completion"]).to be_a(Integer)
      expect(data).to have_key("ready")
    end

    it "persists the checked state" do
      post check_item_organization_release_release_checklist_path(organization, release_id, checklist),
        params: { key: "release_notes_written" },
        as: :json

      checklist.reload
      item = checklist.items.find { |i| i["key"] == "release_notes_written" }
      expect(item["checked"]).to be true
      expect(item["checked_by_id"]).to eq(user.id)
    end
  end

  describe "POST /organizations/:organization_id/releases/:release_id/release_checklists/:id/uncheck_item" do
    before do
      checklist.check_item!("release_notes_written", user)
    end

    it "unchecks an item and returns JSON" do
      post uncheck_item_organization_release_release_checklist_path(organization, release_id, checklist),
        params: { key: "release_notes_written" },
        as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["status"]).to eq("unchecked")
    end

    it "persists the unchecked state" do
      post uncheck_item_organization_release_release_checklist_path(organization, release_id, checklist),
        params: { key: "release_notes_written" },
        as: :json

      checklist.reload
      item = checklist.items.find { |i| i["key"] == "release_notes_written" }
      expect(item["checked"]).to be false
    end
  end

  describe "POST /organizations/:organization_id/releases/:release_id/release_checklists/:id/reset" do
    let!(:checked_checklist) { create(:release_checklist, :all_checked, organization: organization, listable: apple_app, version_string: "2.0.0") }

    it "resets all items and redirects" do
      post reset_organization_release_release_checklist_path(organization, release_id, checked_checklist)

      expect(response).to redirect_to(organization_release_path(organization, release_id))
      checked_checklist.reload
      checked_checklist.items.each do |item|
        expect(item["checked"]).to be false
        expect(item["checked_by_id"]).to be_nil
        expect(item["checked_at"]).to be_nil
      end
    end
  end

  describe "POST /organizations/:organization_id/releases/:release_id/release_checklists/:id/add_custom_item" do
    it "adds a custom item with valid params and returns JSON" do
      post add_custom_item_organization_release_release_checklist_path(organization, release_id, checklist),
        params: { label: "Review with legal", required: "1" },
        as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["custom_items"]).to be_an(Array)
      expect(data["custom_items"].size).to eq(1)
      expect(data["custom_items"].first["label"]).to eq("Review with legal")
      expect(data["custom_items"].first["required"]).to be true
      expect(data).to have_key("completion_percentage")
    end

    it "persists the custom item to the checklist" do
      post add_custom_item_organization_release_release_checklist_path(organization, release_id, checklist),
        params: { label: "Check marketing copy" },
        as: :json

      checklist.reload
      expect(checklist.custom_items.size).to eq(1)
      expect(checklist.custom_items.first["label"]).to eq("Check marketing copy")
      expect(checklist.custom_items.first["created_by_id"]).to eq(user.id)
    end

    it "returns 422 for blank label" do
      post add_custom_item_organization_release_release_checklist_path(organization, release_id, checklist),
        params: { label: "   " },
        as: :json

      expect(response).to have_http_status(:unprocessable_content)
      data = JSON.parse(response.body)
      expect(data["error"]).to be_present
    end

    it "returns 422 for duplicate label" do
      checklist.add_custom_item!(label: "Duplicate item", user: user)

      post add_custom_item_organization_release_release_checklist_path(organization, release_id, checklist),
        params: { label: "duplicate item" },
        as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(checklist.reload.custom_items.size).to eq(1)
    end
  end

  describe "DELETE /organizations/:organization_id/releases/:release_id/release_checklists/:id/remove_custom_item" do
    before do
      checklist.add_custom_item!(label: "Removable item", user: user)
    end

    it "removes the custom item and returns JSON" do
      key = checklist.custom_items.first["key"]

      delete remove_custom_item_organization_release_release_checklist_path(organization, release_id, checklist),
        params: { key: key },
        as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["custom_items"]).to eq([])
      expect(checklist.reload.custom_items).to be_empty
    end

    it "returns 404 for unknown key" do
      delete remove_custom_item_organization_release_release_checklist_path(organization, release_id, checklist),
        params: { key: "not_a_real_key" },
        as: :json

      expect(response).to have_http_status(:not_found)
      data = JSON.parse(response.body)
      expect(data["error"]).to be_present
    end
  end

  describe "authentication" do
    it "redirects unauthenticated users" do
      sign_out user

      get organization_release_release_checklist_path(organization, release_id, checklist)
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "authorization" do
    let(:non_member) { create(:user) }

    before do
      sign_in non_member, scope: :user
    end

    # Non-member tests below assert 404 instead of forbidden/redirect:
    # set_org now scopes the org lookup to current_user.organizations, so
    # an existing-but-not-mine id is indistinguishable from a non-existent
    # id (closes the enumeration oracle). See
    # OrganizationsController#set_organization. Viewer-role tests further
    # down DO still hit Pundit (viewer is a member; their role policy is
    # what fires), so they stay :forbidden.
    it "denies show to non-members" do
      get organization_release_release_checklist_path(organization, release_id, checklist), as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "denies check_item to non-members" do
      post check_item_organization_release_release_checklist_path(organization, release_id, checklist),
        params: { key: "release_notes_written" },
        as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "denies reset to non-members" do
      post reset_organization_release_release_checklist_path(organization, release_id, checklist)
      expect(response).to have_http_status(:not_found)
    end

    context "viewer role" do
      let(:viewer) { create(:user) }

      before do
        create(:membership, user: viewer, organization: organization, role: :viewer)
        sign_in viewer, scope: :user
      end

      it "allows show for viewers" do
        get organization_release_release_checklist_path(organization, release_id, checklist), as: :json
        expect(response).to have_http_status(:ok)
      end

      it "denies check_item for viewers" do
        post check_item_organization_release_release_checklist_path(organization, release_id, checklist),
          params: { key: "release_notes_written" },
          as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it "denies add_custom_item for viewers" do
        post add_custom_item_organization_release_release_checklist_path(organization, release_id, checklist),
          params: { label: "New item" },
          as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it "denies remove_custom_item for viewers" do
        # Seed a custom item as the owner first
        checklist.add_custom_item!(label: "Removable", user: user)
        key = checklist.custom_items.first["key"]

        delete remove_custom_item_organization_release_release_checklist_path(organization, release_id, checklist),
          params: { key: key },
          as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    it "denies add_custom_item to non-members" do
      post add_custom_item_organization_release_release_checklist_path(organization, release_id, checklist),
        params: { label: "Injected item" },
        as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "denies remove_custom_item to non-members" do
      checklist.add_custom_item!(label: "Removable", user: user)
      key = checklist.custom_items.first["key"]

      delete remove_custom_item_organization_release_release_checklist_path(organization, release_id, checklist),
        params: { key: key },
        as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
