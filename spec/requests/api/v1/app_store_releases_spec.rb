require "rails_helper"

RSpec.describe "Api::V1::AppStoreReleases", type: :request do
  let!(:user) { User.create!(email: "dev@example.com", password: "SecurePassword123!", confirmed_at: Time.current) }
  let!(:organization) { Organization.create!(name: "Test Org", owner: user) }
  let!(:token_record) { ApiToken.generate_for(user: user, organization: organization, name: "Test Token", scopes: [ "read", "write" ]) }
  let(:api_token) { token_record[1] }

  let!(:bundle_id) do
    AppleBundleId.create!(
      organization: organization,
      remote_id: "ABC123",
      identifier: "com.example.testapp",
      name: "Test App",
      platform: "IOS"
    )
  end

  # After the cli_defaults migration the endpoint operates on AppleApp.
  # Create a matching AppleApp for every test so the bundle_id filter resolves.
  let!(:apple_app) do
    organization.apple_apps.create!(
      app_store_id: "123456",
      name: "Test App",
      bundle_id: "com.example.testapp"
    )
  end

  let(:headers) do
    {
      "Authorization" => "Bearer #{api_token}",
      "Content-Type" => "application/json"
    }
  end

  describe "GET /api/v1/organizations/:organization_id/app_store_releases" do
    context "when no bundle_id param provided" do
      it "returns all apps with configured cli_defaults for the organization" do
        apple_app.update!(cli_defaults: {
          "release_type" => "AFTER_APPROVAL",
          "version_string" => "1.0.0"
        })

        get "/api/v1/organizations/#{organization.id}/app_store_releases", headers: headers

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["app_store_releases"]).to be_an(Array)
        expect(json["app_store_releases"].length).to eq(1)
      end

      it "excludes apps with no cli_defaults" do
        # apple_app has default `cli_defaults = {}` which should be excluded
        get "/api/v1/organizations/#{organization.id}/app_store_releases", headers: headers

        json = JSON.parse(response.body)
        expect(json["app_store_releases"]).to be_an(Array)
        expect(json["app_store_releases"]).to be_empty
      end
    end

    context "when bundle_id param provided" do
      before do
        apple_app.update!(cli_defaults: {
          "release_type" => "AFTER_APPROVAL",
          "version_string" => "1.0.0"
        })

        # Content fields come from StoreListing, not cli_defaults.
        StoreListing.create!(
          organization: organization,
          listable: apple_app,
          locale: "en-US",
          whats_new: "Bug fixes",
          support_url: "https://example.com/support",
          sync_status: "synced"
        )
      end

      it "returns the release for that bundle ID" do
        get "/api/v1/organizations/#{organization.id}/app_store_releases?bundle_id=#{bundle_id.identifier}",
            headers: headers

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["app_store_releases"]).to be_an(Array)
        expect(json["app_store_releases"].first["bundle_identifier"]).to eq("com.example.testapp")
        expect(json["app_store_releases"].first["whats_new"]).to eq("Bug fixes")
      end

      it "returns 404 when bundle ID not found" do
        get "/api/v1/organizations/#{organization.id}/app_store_releases?bundle_id=com.notfound.app",
            headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 when the app exists but has no cli_defaults configured" do
        # Preserve the legacy AppStoreRelease-backed behavior: apps that were
        # never configured return 404 (the CLI's fetch_release_metadata relies
        # on this to decide whether to proceed without release config).
        apple_app.update!(cli_defaults: {})

        get "/api/v1/organizations/#{organization.id}/app_store_releases?bundle_id=#{bundle_id.identifier}",
            headers: headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/v1/organizations/:organization_id/app_store_releases" do
    let(:valid_params) do
      {
        app_store_release: {
          apple_bundle_id_id: bundle_id.id,
          whats_new: "New features and improvements",
          support_url: "https://example.com/support",
          auto_submit: true,
          version_string: "2.0.0"
        }
      }
    end

    it "creates a new release configuration (writes to apple_apps.cli_defaults)" do
      post "/api/v1/organizations/#{organization.id}/app_store_releases",
           params: valid_params.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["whats_new"]).to eq("New features and improvements")
      expect(json["auto_submit"]).to eq(true)
      expect(json["release_type"]).to eq("AFTER_APPROVAL")
      expect(json["version_string"]).to eq("2.0.0")

      apple_app.reload
      expect(apple_app.cli_defaults["auto_submit"]).to eq(true)
      expect(apple_app.cli_defaults["version_string"]).to eq("2.0.0")
    end

    it "creates release with promotional_text (stored on StoreListing)" do
      params = valid_params.deep_merge(app_store_release: { promotional_text: "Limited time offer!" })

      post "/api/v1/organizations/#{organization.id}/app_store_releases",
           params: params.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["promotional_text"]).to eq("Limited time offer!")

      listing = apple_app.store_listings.find_by(locale: "en-US")
      expect(listing.promotional_text).to eq("Limited time offer!")
    end

    it "creates release with MANUAL release type" do
      params = valid_params.deep_merge(app_store_release: { release_type: "MANUAL" })

      post "/api/v1/organizations/#{organization.id}/app_store_releases",
           params: params.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["release_type"]).to eq("MANUAL")
    end

    it "creates release with SCHEDULED release type and earliest_release_date" do
      scheduled_date = 2.days.from_now.utc.iso8601
      params = valid_params.deep_merge(
        app_store_release: {
          release_type: "SCHEDULED",
          earliest_release_date: scheduled_date
        }
      )

      post "/api/v1/organizations/#{organization.id}/app_store_releases",
           params: params.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["release_type"]).to eq("SCHEDULED")
      expect(json["earliest_release_date"]).to be_present
    end

    it "rejects SCHEDULED release type without earliest_release_date" do
      params = valid_params.deep_merge(app_store_release: { release_type: "SCHEDULED" })
      params[:app_store_release].delete(:version_string) # avoid cli_defaults save side-effect

      post "/api/v1/organizations/#{organization.id}/app_store_releases",
           params: params.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["details"]).to include(a_string_matching(/earliest release date/i))
    end

    it "persists localizations array through strong params (regression: arrays were silently stripped)" do
      params = valid_params.deep_merge(
        app_store_release: {
          localizations: [
            { "locale" => "en-US", "whats_new" => "English" },
            { "locale" => "fr-FR", "whats_new" => "French" }
          ]
        }
      )

      post "/api/v1/organizations/#{organization.id}/app_store_releases",
           params: params.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      apple_app.reload
      expect(apple_app.cli_defaults["localizations"]).to be_an(Array)
      expect(apple_app.cli_defaults["localizations"].size).to eq(2)
      expect(apple_app.cli_defaults["localizations"].first["locale"]).to eq("en-US")
    end

    it "validates build_number is a positive integer" do
      params = valid_params.deep_merge(app_store_release: { build_number: "abc" })

      post "/api/v1/organizations/#{organization.id}/app_store_releases",
           params: params.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["details"]).to include(a_string_matching(/build number/i))
    end

    it "forwards content fields to StoreListing on create" do
      post "/api/v1/organizations/#{organization.id}/app_store_releases",
           params: valid_params.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      listing = apple_app.store_listings.find_by(locale: "en-US")
      expect(listing).to be_present
      expect(listing.whats_new).to eq("New features and improvements")
      expect(listing.support_url).to eq("https://example.com/support")
    end

    context "when the apple app has a non-en-US primary locale" do
      before do
        apple_app.update!(
          raw_json: {
            "attributes" => { "primaryLocale" => "en-GB" }
          }
        )
      end

      it "writes whats_new to the en-GB store listing, not en-US" do
        params = valid_params.deep_merge(
          app_store_release: { whats_new: "British release notes" }
        )

        post "/api/v1/organizations/#{organization.id}/app_store_releases",
             params: params.to_json,
             headers: headers

        expect(response).to have_http_status(:created)

        listing = apple_app.store_listings.find_by(locale: "en-GB")
        expect(listing).not_to be_nil
        expect(listing.whats_new).to eq("British release notes")

        # Critically, no en-US listing should have been created.
        expect(apple_app.store_listings.find_by(locale: "en-US")).to be_nil
      end
    end

    it "returns conflict when release already exists for bundle ID" do
      # Pre-populate cli_defaults so the create is a conflict
      apple_app.update!(cli_defaults: { "release_type" => "AFTER_APPROVAL", "auto_submit" => true })

      post "/api/v1/organizations/#{organization.id}/app_store_releases",
           params: valid_params.to_json,
           headers: headers

      expect(response).to have_http_status(:conflict)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("conflict")
      expect(json["message"]).to include("already exists")
      expect(json["details"]["resource_id"]).to be_present
    end
  end

  describe "PATCH /api/v1/organizations/:organization_id/app_store_releases/:id" do
    before do
      apple_app.update!(cli_defaults: {
        "release_type" => "AFTER_APPROVAL",
        "version_string" => "3.0.0"
      })
      StoreListing.create!(
        organization: organization,
        listable: apple_app,
        locale: "en-US",
        whats_new: "Old notes",
        sync_status: "synced"
      )
    end

    it "updates the release configuration" do
      patch "/api/v1/organizations/#{organization.id}/app_store_releases/#{apple_app.id}",
            params: { app_store_release: { whats_new: "Updated notes" } }.to_json,
            headers: headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["whats_new"]).to eq("Updated notes")
    end

    it "updates release_type" do
      patch "/api/v1/organizations/#{organization.id}/app_store_releases/#{apple_app.id}",
            params: { app_store_release: { release_type: "MANUAL" } }.to_json,
            headers: headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["release_type"]).to eq("MANUAL")
    end

    it "updates to SCHEDULED with earliest_release_date" do
      scheduled_date = 3.days.from_now.utc.iso8601

      patch "/api/v1/organizations/#{organization.id}/app_store_releases/#{apple_app.id}",
            params: {
              app_store_release: {
                release_type: "SCHEDULED",
                earliest_release_date: scheduled_date
              }
            }.to_json,
            headers: headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["release_type"]).to eq("SCHEDULED")
      expect(json["earliest_release_date"]).to be_present
    end
  end

  describe "GET /api/v1/organizations/:organization_id/app_store_releases/:id" do
    before do
      apple_app.update!(cli_defaults: {
        "release_type" => "MANUAL",
        "phased_release" => true,
        "build_number" => "42",
        "version_string" => "1.0.0"
      })
    end

    it "returns release with all strategy fields" do
      get "/api/v1/organizations/#{organization.id}/app_store_releases/#{apple_app.id}",
          headers: headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["release_type"]).to eq("MANUAL")
      expect(json["phased_release"]).to eq(true)
      expect(json["build_number"]).to eq("42")
    end

    it "sources content fields from StoreListing when available" do
      StoreListing.create!(
        organization: organization,
        listable: apple_app,
        locale: "en-US",
        whats_new: "From store listing",
        support_url: "https://listing.example.com/support",
        sync_status: "synced"
      )

      get "/api/v1/organizations/#{organization.id}/app_store_releases/#{apple_app.id}",
          headers: headers

      json = JSON.parse(response.body)
      expect(json["whats_new"]).to eq("From store listing")
      expect(json["support_url"]).to eq("https://listing.example.com/support")
    end

    it "returns null content fields when no StoreListing exists" do
      get "/api/v1/organizations/#{organization.id}/app_store_releases/#{apple_app.id}",
          headers: headers

      json = JSON.parse(response.body)
      expect(json["whats_new"]).to be_nil
    end
  end

  describe "authorization" do
    context "with read-only token" do
      let!(:read_token_record) { ApiToken.generate_for(user: user, organization: organization, name: "Read Token", scopes: [ "read" ]) }
      let(:read_api_token) { read_token_record[1] }

      let(:read_headers) do
        {
          "Authorization" => "Bearer #{read_api_token}",
          "Content-Type" => "application/json"
        }
      end

      it "allows read operations" do
        apple_app.update!(cli_defaults: { "release_type" => "AFTER_APPROVAL" })

        get "/api/v1/organizations/#{organization.id}/app_store_releases",
            headers: read_headers

        expect(response).to have_http_status(:success)
      end

      it "rejects write operations" do
        post "/api/v1/organizations/#{organization.id}/app_store_releases",
             params: { app_store_release: { apple_bundle_id_id: bundle_id.id } }.to_json,
             headers: read_headers

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
