require "rails_helper"

RSpec.describe "Api::V1::PlayStoreReleases", type: :request do
  let!(:user) { User.create!(email: "dev@example.com", password: "SecurePassword123!", confirmed_at: Time.current) }
  let!(:organization) { Organization.create!(name: "Test Org", owner: user) }
  let!(:token_record) { ApiToken.generate_for(user: user, organization: organization, name: "Test Token", scopes: [ "read", "write" ]) }
  let(:api_token) { token_record[1] }

  let(:headers) do
    {
      "Authorization" => "Bearer #{api_token}",
      "Content-Type" => "application/json"
    }
  end

  describe "GET /api/v1/organizations/:organization_id/play_store_releases" do
    it "lists releases or returns one by package_name" do
      app1 = AndroidApp.create!(organization: organization, package_name: "com.example.one", name: "One")
      app2 = AndroidApp.create!(organization: organization, package_name: "com.example.two", name: "Two")
      PlayStoreRelease.create!(android_app: app1, track: "beta", release_notes: "Beta notes", version_code: "101", status: "draft")
      PlayStoreRelease.create!(android_app: app2, track: "production", release_notes: "Prod notes", version_code: "202", status: "live")

      get "/api/v1/organizations/#{organization.id}/play_store_releases", headers: headers
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["play_store_releases"].length).to eq(2)

      get "/api/v1/organizations/#{organization.id}/play_store_releases?package_name=com.example.one", headers: headers
      expect(response).to have_http_status(:success)
      json2 = JSON.parse(response.body)
      expect(json2["play_store_releases"].length).to eq(1)
      expect(json2["play_store_releases"].first["package_name"]).to eq("com.example.one")
      expect(json2["play_store_releases"].first["track"]).to eq("beta")
    end
  end

  describe "POST /api/v1/organizations/:organization_id/play_store_releases" do
    it "creates a release config for an android app" do
      app = AndroidApp.create!(organization: organization, package_name: "com.example.new", name: "New")
      params = {
        play_store_release: {
          android_app_id: app.id,
          track: "beta",
          release_notes: "Notes",
          auto_submit: true,
          localizations: { "en-US" => { "whats_new" => "Notes" } },
          version_code: "303",
          status: "submitted"
        }
      }

      expect {
        post "/api/v1/organizations/#{organization.id}/play_store_releases",
             params: params.to_json,
             headers: headers
      }.to change(PlayStoreRelease, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["track"]).to eq("beta")
      expect(json["package_name"]).to eq("com.example.new")
    end

    it "allows multiple releases per app and status" do
      app = AndroidApp.create!(organization: organization, package_name: "com.example.x", name: "X")
      PlayStoreRelease.create!(android_app: app, track: "beta", version_code: "400", status: "draft")

      post "/api/v1/organizations/#{organization.id}/play_store_releases",
           params: {
             play_store_release: {
               android_app_id: app.id,
               track: "production",
               version_code: "400",
               status: "submitted"
             }
           }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["status"]).to eq("submitted")
    end
  end

  describe "PATCH /api/v1/organizations/:organization_id/play_store_releases/:id" do
    it "updates a release and forwards release_notes to StoreListing" do
      app = AndroidApp.create!(organization: organization, package_name: "com.example.u", name: "U")
      rel = PlayStoreRelease.create!(android_app: app, track: "beta", release_notes: "Old", version_code: "777", status: "draft")

      patch "/api/v1/organizations/#{organization.id}/play_store_releases/#{rel.id}",
            params: { play_store_release: { release_notes: "New" } }.to_json,
            headers: headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["release_notes"]).to eq("New")

      listing = app.store_listings.find_by(locale: "en-US")
      expect(listing).to be_present
      expect(listing.whats_new).to eq("New")
    end
  end

  describe "content sourcing from StoreListing" do
    it "sources release_notes from StoreListing when available" do
      app = AndroidApp.create!(organization: organization, package_name: "com.example.sl", name: "SL")
      rel = PlayStoreRelease.create!(android_app: app, track: "production", release_notes: "Old notes", version_code: "100", status: "live")
      StoreListing.create!(
        organization: organization,
        listable: app,
        locale: "en-US",
        whats_new: "Notes from store listing",
        sync_status: "synced"
      )

      get "/api/v1/organizations/#{organization.id}/play_store_releases/#{rel.id}",
          headers: headers

      json = JSON.parse(response.body)
      expect(json["release_notes"]).to eq("Notes from store listing")
    end

    it "falls back to PlayStoreRelease.release_notes when no StoreListing" do
      app = AndroidApp.create!(organization: organization, package_name: "com.example.fb", name: "FB")
      rel = PlayStoreRelease.create!(android_app: app, track: "beta", release_notes: "Fallback notes", version_code: "200", status: "draft")

      get "/api/v1/organizations/#{organization.id}/play_store_releases/#{rel.id}",
          headers: headers

      json = JSON.parse(response.body)
      expect(json["release_notes"]).to eq("Fallback notes")
    end
  end

  describe "non-en-US primary locale coverage" do
    context "when the android app has a non-en-US default_language" do
      let!(:android_app_de) do
        AndroidApp.create!(
          organization: organization,
          package_name: "com.example.de",
          name: "Deutsche App",
          default_language: "de-DE"
        )
      end

      it "writes whats_new to the de-DE store listing on create, not en-US" do
        params = {
          play_store_release: {
            android_app_id: android_app_de.id,
            track: "production",
            release_notes: "Deutsche release notes",
            version_code: "500",
            status: "draft"
          }
        }

        post "/api/v1/organizations/#{organization.id}/play_store_releases",
             params: params.to_json,
             headers: headers

        expect(response).to have_http_status(:created)

        listing = android_app_de.store_listings.find_by(locale: "de-DE")
        expect(listing).not_to be_nil
        expect(listing.whats_new).to eq("Deutsche release notes")

        # No en-US listing should have been created.
        expect(android_app_de.store_listings.find_by(locale: "en-US")).to be_nil
      end

      it "writes whats_new to the de-DE store listing on update, not en-US" do
        rel = PlayStoreRelease.create!(
          android_app: android_app_de,
          track: "production",
          release_notes: "Alt",
          version_code: "600",
          status: "draft"
        )

        patch "/api/v1/organizations/#{organization.id}/play_store_releases/#{rel.id}",
              params: { play_store_release: { release_notes: "Neu" } }.to_json,
              headers: headers

        expect(response).to have_http_status(:success)

        listing = android_app_de.store_listings.find_by(locale: "de-DE")
        expect(listing).not_to be_nil
        expect(listing.whats_new).to eq("Neu")

        expect(android_app_de.store_listings.find_by(locale: "en-US")).to be_nil
      end

      it "reads release_notes from the de-DE store listing on show" do
        rel = PlayStoreRelease.create!(
          android_app: android_app_de,
          track: "production",
          release_notes: "Fallback",
          version_code: "700",
          status: "live"
        )
        StoreListing.create!(
          organization: organization,
          listable: android_app_de,
          locale: "de-DE",
          whats_new: "Deutsche notes from store listing",
          sync_status: "synced"
        )

        get "/api/v1/organizations/#{organization.id}/play_store_releases/#{rel.id}",
            headers: headers

        json = JSON.parse(response.body)
        expect(json["release_notes"]).to eq("Deutsche notes from store listing")
      end
    end
  end
end
