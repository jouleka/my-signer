require "rails_helper"

RSpec.describe "Api::V1::AppStoreVersions", type: :request do
  let!(:user) { User.create!(email: "dev@example.com", password: "SecurePassword123!", confirmed_at: Time.current) }
  let!(:organization) { Organization.create!(name: "Test Org", owner: user) }
  let!(:token_record) { ApiToken.generate_for(user: user, organization: organization, name: "Test Token", scopes: [ "read", "write" ]) }
  let(:api_token) { token_record[1] }

  let!(:credential) do
    AppStoreConnectCredential.create!(
      organization: organization,
      name: "Test Credential",
      key_id: "ABC12345XY",
      issuer_id: "DEF456789-1234567890-ABC",
      private_key: "-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----",
      active: true
    )
  end

  let!(:apple_app) do
    AppleApp.create!(
      organization: organization,
      app_store_id: "123456789",
      bundle_id: "com.example.app",
      name: "Test App"
    )
  end

  let!(:app_store_version) do
    AppStoreVersion.create!(
      organization: organization,
      apple_app: apple_app,
      version_id: "v-123456",
      version_string: "1.0.0",
      platform: "IOS",
      app_store_state: "PREPARE_FOR_SUBMISSION",
      phased_release_pending: false
    )
  end

  let!(:apple_build) do
    AppleBuild.create!(
      organization: organization,
      apple_app: apple_app,
      build_id: "b-123456",
      version: "1.0.0",
      build_number: "1",
      processing_state: "VALID"
    )
  end

  let(:headers) do
    {
      "Authorization" => "Bearer #{api_token}",
      "Content-Type" => "application/json"
    }
  end

  # Mock Apple API client
  let(:mock_client) { instance_double(AppStoreConnect::Client) }
  let(:mock_versions_service) { instance_double(AppStoreConnect::Versions) }

  before do
    allow(AppStoreConnect::Client).to receive(:new).and_return(mock_client)
    allow(AppStoreConnect::Versions).to receive(:new).and_return(mock_versions_service)
  end

  describe "POST /api/v1/organizations/:organization_id/app_store_versions/:id/phased_release" do
    context "activate action" do
      it "activates phased release when eligible" do
        allow(mock_versions_service).to receive(:phased_release_eligibility)
          .with(version_id: app_store_version.version_id)
          .and_return(:can_activate)

        allow(mock_versions_service).to receive(:create_phased_release)
          .with(version_id: app_store_version.version_id, state: "ACTIVE")
          .and_return({ "data" => { "id" => "pr-123" } })

        post "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/phased_release",
             params: { action_type: "activate" }.to_json,
             headers: headers

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["message"]).to eq("Phased release activated")
        expect(app_store_version.reload.phased_release_pending).to be(false)
      end

      it "returns already_active message if phased release is already active" do
        allow(mock_versions_service).to receive(:phased_release_eligibility)
          .with(version_id: app_store_version.version_id)
          .and_return(:already_active)

        post "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/phased_release",
             params: { action_type: "activate" }.to_json,
             headers: headers

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["message"]).to eq("Phased release already active")
      end

      it "queues background job when pending review" do
        allow(mock_versions_service).to receive(:phased_release_eligibility)
          .with(version_id: app_store_version.version_id)
          .and_return(:pending_review)

        expect {
          post "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/phased_release",
               params: { action_type: "activate" }.to_json,
               headers: headers
        }.to have_enqueued_job(PhasedReleaseActivationJob).with(app_store_version.id)

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["message"]).to eq("Phased release will be activated after app approval")
        expect(app_store_version.reload.phased_release_pending).to be(true)
      end

      it "returns error for removed_from_sale" do
        allow(mock_versions_service).to receive(:phased_release_eligibility)
          .with(version_id: app_store_version.version_id)
          .and_return(:removed_from_sale)

        post "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/phased_release",
             params: { action_type: "activate" }.to_json,
             headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("invalid_state")
      end
    end

    context "pause action" do
      it "pauses an active phased release" do
        allow(mock_versions_service).to receive(:phased_release)
          .with(version_id: app_store_version.version_id)
          .and_return({ "id" => "pr-123" })

        allow(mock_versions_service).to receive(:update_phased_release)
          .with(phased_release_id: "pr-123", state: "PAUSE")
          .and_return({ "data" => { "id" => "pr-123" } })

        post "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/phased_release",
             params: { action_type: "pause" }.to_json,
             headers: headers

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["message"]).to eq("Phased release paused")
      end

      it "returns error if no active phased release found" do
        allow(mock_versions_service).to receive(:phased_release)
          .with(version_id: app_store_version.version_id)
          .and_return(nil)

        post "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/phased_release",
             params: { action_type: "pause" }.to_json,
             headers: headers

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("not_found")
      end
    end

    context "resume action" do
      it "resumes a paused phased release" do
        allow(mock_versions_service).to receive(:phased_release)
          .with(version_id: app_store_version.version_id)
          .and_return({ "id" => "pr-123" })

        allow(mock_versions_service).to receive(:update_phased_release)
          .with(phased_release_id: "pr-123", state: "ACTIVE")
          .and_return({ "data" => { "id" => "pr-123" } })

        post "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/phased_release",
             params: { action_type: "resume" }.to_json,
             headers: headers

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["message"]).to eq("Phased release resumed")
      end
    end

    context "complete action" do
      it "completes a phased release" do
        allow(mock_versions_service).to receive(:phased_release)
          .with(version_id: app_store_version.version_id)
          .and_return({ "id" => "pr-123" })

        allow(mock_versions_service).to receive(:update_phased_release)
          .with(phased_release_id: "pr-123", state: "COMPLETE")
          .and_return({ "data" => { "id" => "pr-123" } })

        post "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/phased_release",
             params: { action_type: "complete" }.to_json,
             headers: headers

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["message"]).to eq("Phased release completed - app now available to all users")
      end
    end

    context "invalid action" do
      it "returns error for invalid action" do
        post "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/phased_release",
             params: { action_type: "invalid" }.to_json,
             headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("invalid_request")
      end
    end

    context "without active credential" do
      before do
        credential.update!(active: false)
      end

      it "returns configuration_required error" do
        post "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/phased_release",
             params: { action_type: "activate" }.to_json,
             headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("credentials_required")
      end
    end

    context "with read-only token" do
      let!(:read_token_record) { ApiToken.generate_for(user: user, organization: organization, name: "Read Token", scopes: [ "read" ]) }
      let(:read_api_token) { read_token_record[1] }

      let(:read_headers) do
        {
          "Authorization" => "Bearer #{read_api_token}",
          "Content-Type" => "application/json"
        }
      end

      it "rejects write operations" do
        post "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/phased_release",
             params: { action_type: "activate" }.to_json,
             headers: read_headers

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /api/v1/organizations/:organization_id/app_store_versions/:id/submit" do
    before do
      app_store_version.update!(apple_build: apple_build)
    end

    it "triggers phased release job when phased_release param is true" do
      allow(mock_versions_service).to receive(:localizations).and_return([])
      allow(mock_versions_service).to receive(:create_localization)
      allow(mock_versions_service).to receive(:submit_for_review).and_return({ "data" => {} })

      expect {
        post "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/submit",
             params: { whats_new: "Bug fixes", phased_release: true }.to_json,
             headers: headers
      }.to have_enqueued_job(PhasedReleaseActivationJob).with(app_store_version.id)

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["message"]).to include("Phased release will be activated after app approval")
      expect(app_store_version.reload.phased_release_pending).to be(true)
    end

    it "does not trigger phased release when param is false" do
      allow(mock_versions_service).to receive(:localizations).and_return([])
      allow(mock_versions_service).to receive(:create_localization)
      allow(mock_versions_service).to receive(:submit_for_review).and_return({ "data" => {} })

      expect {
        post "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/submit",
             params: { whats_new: "Bug fixes", phased_release: false }.to_json,
             headers: headers
      }.not_to have_enqueued_job(PhasedReleaseActivationJob)

      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /api/v1/organizations/:organization_id/app_store_versions with release_type" do
    it "creates version with SCHEDULED release type and earliest_release_date" do
      scheduled_date = 2.days.from_now.utc.iso8601

      allow(mock_versions_service).to receive(:editable_versions)
        .with(app_id: apple_app.app_store_id)
        .and_return([])

      allow(mock_versions_service).to receive(:create)
        .and_return({
          "data" => {
            "id" => "new-version-id",
            "attributes" => {
              "versionString" => "2.0.0",
              "appStoreState" => "PREPARE_FOR_SUBMISSION",
              "releaseType" => "SCHEDULED",
              "earliestReleaseDate" => scheduled_date
            }
          }
        })

      post "/api/v1/organizations/#{organization.id}/app_store_versions",
           params: {
             app_store_version: {
               app_id: apple_app.id,
               version_string: "2.0.0",
               release_type: "SCHEDULED",
               earliest_release_date: scheduled_date
             }
           }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["data"]["version_string"]).to eq("2.0.0")
      expect(json["data"]["release_type"]).to eq("SCHEDULED")
    end

    it "creates version with MANUAL release type" do
      allow(mock_versions_service).to receive(:editable_versions)
        .with(app_id: apple_app.app_store_id)
        .and_return([])

      allow(mock_versions_service).to receive(:create)
        .and_return({
          "data" => {
            "id" => "new-version-id",
            "attributes" => {
              "versionString" => "2.0.0",
              "appStoreState" => "PREPARE_FOR_SUBMISSION",
              "releaseType" => "MANUAL"
            }
          }
        })

      post "/api/v1/organizations/#{organization.id}/app_store_versions",
           params: {
             app_store_version: {
               app_id: apple_app.id,
               version_string: "2.0.0",
               release_type: "MANUAL"
             }
           }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
    end
  end

  describe "GET /api/v1/organizations/:organization_id/app_store_versions/:id" do
    it "includes release_type and phased_release_pending in response" do
      app_store_version.update!(
        phased_release_pending: true,
        raw_json: { "attributes" => { "releaseType" => "SCHEDULED", "earliestReleaseDate" => "2026-02-01T00:00:00Z" } }
      )

      get "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}",
          headers: headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["data"]["release_type"]).to eq("SCHEDULED")
      expect(json["data"]["earliest_release_date"]).to eq("2026-02-01T00:00:00Z")
      expect(json["data"]["phased_release_pending"]).to be(true)
    end
  end
end
