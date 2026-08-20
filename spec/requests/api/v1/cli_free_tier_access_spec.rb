require "rails_helper"

# These specs lock in the contract that the CLI's core signing workflow is
# available to ALL plan tiers, including Free. The CLI itself does not upload
# screenshots or manage store listings; it handles signing, build, ship,
# profiles, certificates, keystores, sync, and release configs.
#
# If any of these endpoints starts rejecting free-tier tokens, the CLI is
# broken for new/free users -- which is a regression against our product
# commitment.
RSpec.describe "API endpoints used by the CLI are free for all tiers", type: :request do
  let(:user) { User.create!(email: "cli-free@example.com", password: "SecurePassword123!", confirmed_at: Time.current) }
  let(:organization) { Organization.create!(name: "Free Org", owner: user) }
  let(:token_record) { ApiToken.generate_for(user: user, organization: organization, name: "CLI Token", scopes: [ "read", "write" ]) }
  let(:api_token) { token_record[1] }

  let(:headers) do
    {
      "Authorization" => "Bearer #{api_token}",
      "X-User-Email" => user.email
    }
  end

  before do
    # Explicitly confirm user is on free plan -- no implicit team/pro inheritance.
    user.update_column(:plan_tier, User.plan_tiers[:free])
    expect(user.reload.plan_tier).to eq("free")
  end

  describe "auth & discovery" do
    it "GET /api/v1/status succeeds for free user" do
      get "/api/v1/status", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "GET /api/v1/user/organizations lists user's orgs for free user" do
      get "/api/v1/user/organizations", headers: headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      # Endpoint returns { organizations: [...], total: N }
      expect(json).to include("organizations")
      expect(json["organizations"]).to be_an(Array)
      expect(json["organizations"].first["id"]).to eq(organization.id)
    end

    it "GET /api/v1/organizations/:id succeeds for free user" do
      get "/api/v1/organizations/#{organization.id}", headers: headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe "resource reads (certificates/profiles/devices/apps/builds)" do
    it "GET /api/v1/organizations/:id/certificates succeeds" do
      get "/api/v1/organizations/#{organization.id}/certificates", headers: headers
      # Without credentials this may return 200 with empty list, or a specific
      # error -- but NEVER a plan-upgrade-required response.
      expect(response.body).not_to include("plan_upgrade_required")
      expect([ 200, 422 ]).to include(response.status), "Expected 200 or 422 (not 402/403 plan-gate), got #{response.status}"
    end

    it "GET /api/v1/organizations/:id/profiles succeeds" do
      get "/api/v1/organizations/#{organization.id}/profiles", headers: headers
      expect(response.body).not_to include("plan_upgrade_required")
      expect([ 200, 422 ]).to include(response.status)
    end

    it "GET /api/v1/organizations/:id/devices succeeds" do
      get "/api/v1/organizations/#{organization.id}/devices", headers: headers
      expect(response.body).not_to include("plan_upgrade_required")
      expect([ 200, 422 ]).to include(response.status)
    end

    it "GET /api/v1/organizations/:id/apple_apps succeeds" do
      get "/api/v1/organizations/#{organization.id}/apple_apps", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("plan_upgrade_required")
    end

    it "GET /api/v1/organizations/:id/android_apps succeeds" do
      get "/api/v1/organizations/#{organization.id}/android_apps", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("plan_upgrade_required")
    end

    it "GET /api/v1/organizations/:id/builds succeeds" do
      get "/api/v1/organizations/#{organization.id}/builds", headers: headers
      expect(response.body).not_to include("plan_upgrade_required")
      expect([ 200, 422 ]).to include(response.status)
    end
  end

  describe "sync (the core CLI workflow)" do
    it "POST /api/v1/organizations/:id/sync works without plan gate" do
      post "/api/v1/organizations/#{organization.id}/sync", headers: headers
      # May return 422 if no credentials exist, but NEVER a plan upgrade error.
      expect(response.body).not_to include("plan_upgrade_required")
      expect(response.body).not_to include("requires a Pro plan")
      expect(response.body).not_to include("requires a Team plan")
    end

    it "GET /api/v1/organizations/:id/sync/status works without plan gate" do
      get "/api/v1/organizations/#{organization.id}/sync/status", headers: headers
      expect(response.body).not_to include("plan_upgrade_required")
      expect([ 200, 422 ]).to include(response.status)
    end
  end

  describe "release & submission endpoints (the ship workflow)" do
    it "GET /api/v1/organizations/:id/app_store_releases succeeds" do
      get "/api/v1/organizations/#{organization.id}/app_store_releases", headers: headers
      expect(response.body).not_to include("plan_upgrade_required")
      expect([ 200, 422 ]).to include(response.status)
    end
  end

  describe "resource lookups (bundle_ids, keystores, credentials)" do
    it "GET /api/v1/organizations/:id/bundle_ids succeeds" do
      get "/api/v1/organizations/#{organization.id}/bundle_ids", headers: headers
      expect(response.body).not_to include("plan_upgrade_required")
      expect([ 200, 422 ]).to include(response.status)
    end

    it "GET /api/v1/organizations/:id/android_keystores succeeds" do
      get "/api/v1/organizations/#{organization.id}/android_keystores", headers: headers
      expect(response.body).not_to include("plan_upgrade_required")
      expect([ 200, 422 ]).to include(response.status)
    end
  end
end
