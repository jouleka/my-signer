require "rails_helper"

RSpec.describe "Api::V1::AppInfo", type: :request do
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

  let(:headers) do
    {
      "Authorization" => "Bearer #{api_token}",
      "Content-Type" => "application/json"
    }
  end

  # Mock Apple API client and service
  let(:mock_client) { instance_double(AppStoreConnect::Client) }
  let(:mock_app_info_service) { instance_double(AppStoreConnect::AppInfo) }

  before do
    allow(AppStoreConnect::Client).to receive(:new).and_return(mock_client)
    allow(AppStoreConnect::AppInfo).to receive(:new).and_return(mock_app_info_service)
  end

  describe "GET /api/v1/organizations/:organization_id/apple_apps/:apple_app_id/app_info" do
    let(:app_info_response) do
      {
        "id" => "ai-123456",
        "attributes" => {
          "state" => "READY_FOR_SUBMISSION"
        }
      }
    end

    let(:localizations_response) do
      [
        {
          "id" => "loc-en",
          "attributes" => {
            "locale" => "en-US",
            "name" => "Test App",
            "subtitle" => "The best app",
            "privacyPolicyText" => "We care about privacy",
            "privacyChoicesUrl" => "https://example.com/privacy-choices",
            "privacyPolicyUrl" => "https://example.com/privacy"
          }
        },
        {
          "id" => "loc-de",
          "attributes" => {
            "locale" => "de-DE",
            "name" => "Test App DE",
            "subtitle" => "Die beste App"
          }
        }
      ]
    end

    it "returns app info with localizations" do
      allow(mock_app_info_service).to receive(:primary)
        .with(app_id: apple_app.app_store_id)
        .and_return(app_info_response)

      allow(mock_app_info_service).to receive(:localizations)
        .with(app_info_id: "ai-123456")
        .and_return(localizations_response)

      get "/api/v1/organizations/#{organization.id}/apple_apps/#{apple_app.id}/app_info",
          headers: headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)

      expect(json["data"]["app_info_id"]).to eq("ai-123456")
      expect(json["data"]["state"]).to eq("READY_FOR_SUBMISSION")
      expect(json["data"]["localizations"]).to be_an(Array)
      expect(json["data"]["localizations"].length).to eq(2)

      en_loc = json["data"]["localizations"].find { |l| l["locale"] == "en-US" }
      expect(en_loc["name"]).to eq("Test App")
      expect(en_loc["subtitle"]).to eq("The best app")
      expect(en_loc["privacy_policy_url"]).to eq("https://example.com/privacy")
    end

    it "returns 404 when app info not found" do
      allow(mock_app_info_service).to receive(:primary)
        .with(app_id: apple_app.app_store_id)
        .and_return(nil)

      get "/api/v1/organizations/#{organization.id}/apple_apps/#{apple_app.id}/app_info",
          headers: headers

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("not_found")
    end

    it "returns 404 for non-existent apple app" do
      get "/api/v1/organizations/#{organization.id}/apple_apps/999999/app_info",
          headers: headers

      expect(response).to have_http_status(:not_found)
    end

    context "without active credential" do
      before do
        credential.update!(active: false)
      end

      it "returns configuration_required error" do
        get "/api/v1/organizations/#{organization.id}/apple_apps/#{apple_app.id}/app_info",
            headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("credentials_required")
      end
    end
  end

  describe "PATCH /api/v1/organizations/:organization_id/apple_apps/:apple_app_id/app_info" do
    let(:updated_localization) do
      {
        "data" => {
          "id" => "loc-en",
          "attributes" => {
            "locale" => "en-US",
            "name" => "Updated App",
            "subtitle" => "New subtitle"
          }
        }
      }
    end

    it "updates app info localization" do
      allow(mock_app_info_service).to receive(:update_by_locale)
        .with(
          app_id: apple_app.app_store_id,
          locale: "en-US",
          subtitle: "New subtitle"
        )
        .and_return(updated_localization)

      patch "/api/v1/organizations/#{organization.id}/apple_apps/#{apple_app.id}/app_info",
            params: { locale: "en-US", subtitle: "New subtitle" }.to_json,
            headers: headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["message"]).to eq("App info updated successfully")
      expect(json["data"]["subtitle"]).to eq("New subtitle")
    end

    it "updates multiple attributes" do
      allow(mock_app_info_service).to receive(:update_by_locale)
        .with(
          app_id: apple_app.app_store_id,
          locale: "en-US",
          subtitle: "New subtitle",
          name: "New Name",
          privacy_policy_url: "https://example.com/new-privacy"
        )
        .and_return(updated_localization)

      patch "/api/v1/organizations/#{organization.id}/apple_apps/#{apple_app.id}/app_info",
            params: {
              locale: "en-US",
              subtitle: "New subtitle",
              name: "New Name",
              privacy_policy_url: "https://example.com/new-privacy"
            }.to_json,
            headers: headers

      expect(response).to have_http_status(:success)
    end

    it "uses default locale en-US when not provided" do
      allow(mock_app_info_service).to receive(:update_by_locale)
        .with(
          app_id: apple_app.app_store_id,
          locale: "en-US",
          subtitle: "Default locale subtitle"
        )
        .and_return(updated_localization)

      patch "/api/v1/organizations/#{organization.id}/apple_apps/#{apple_app.id}/app_info",
            params: { subtitle: "Default locale subtitle" }.to_json,
            headers: headers

      expect(response).to have_http_status(:success)
    end

    it "returns error when no attributes provided" do
      patch "/api/v1/organizations/#{organization.id}/apple_apps/#{apple_app.id}/app_info",
            params: { locale: "en-US" }.to_json,
            headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("invalid_request")
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
        patch "/api/v1/organizations/#{organization.id}/apple_apps/#{apple_app.id}/app_info",
              params: { subtitle: "Test" }.to_json,
              headers: read_headers

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when Apple API fails" do
      it "returns update_failed error" do
        allow(mock_app_info_service).to receive(:update_by_locale)
          .and_raise(StandardError.new("Apple API error"))

        patch "/api/v1/organizations/#{organization.id}/apple_apps/#{apple_app.id}/app_info",
              params: { subtitle: "Test" }.to_json,
              headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("operation_failed")
        expect(json["message"]).to include("Apple API error")
      end
    end
  end
end
