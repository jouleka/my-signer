require "rails_helper"

RSpec.describe "Api::V1::AndroidTracks", type: :request do
  let!(:user) { User.create!(email: "dev@example.com", password: "SecurePassword123!", confirmed_at: Time.current) }
  let!(:organization) { Organization.create!(name: "Test Org", owner: user) }
  let!(:token_record) { ApiToken.generate_for(user: user, organization: organization, name: "Test Token", scopes: [ "read" ]) }
  let(:api_token) { token_record[1] }

  let(:headers) do
    {
      "Authorization" => "Bearer #{api_token}",
      "Content-Type" => "application/json"
    }
  end

  describe "GET /api/v1/organizations/:organization_id/android_apps/package/:package_name/tracks" do
    it "lists tracks for an app" do
      app = AndroidApp.create!(organization: organization, package_name: "com.example.app", name: "App")
      AndroidTrack.create!(android_app: app, track_name: "beta", status: "active", releases: { version_codes: [ 1, 2 ] })
      AndroidTrack.create!(android_app: app, track_name: "production", status: "inactive", releases: {})

      get "/api/v1/organizations/#{organization.id}/android_apps/package/com.example.app/tracks", headers: headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["package_name"]).to eq("com.example.app")
      expect(json["tracks"].map { |t| t["track_name"] }).to include("beta", "production")
    end
  end

  describe "GET /api/v1/organizations/:organization_id/android_apps/package/:package_name/tracks/:track" do
    it "shows a track" do
      app = AndroidApp.create!(organization: organization, package_name: "com.example.app", name: "App")
      AndroidTrack.create!(android_app: app, track_name: "beta", status: "active", releases: { version_codes: [ 3 ] })

      get "/api/v1/organizations/#{organization.id}/android_apps/package/com.example.app/tracks/beta", headers: headers
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["track_name"]).to eq("beta")
      expect(json["releases"]).to eq({ "version_codes" => [ 3 ] })
    end

    it "404s when track missing" do
      app = AndroidApp.create!(organization: organization, package_name: "com.example.app", name: "App")

      get "/api/v1/organizations/#{organization.id}/android_apps/package/com.example.app/tracks/bogus", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
