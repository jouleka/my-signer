require "rails_helper"

RSpec.describe "Api::V1::AppStoreVersionLocalizations", type: :request do
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
      app_store_state: "PREPARE_FOR_SUBMISSION"
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
  let(:mock_versions_service) { instance_double(AppStoreConnect::Versions) }

  # Stub used by the localization ID cross-check in update/destroy
  let(:ownership_check_localizations) do
    [
      { "id" => "loc-en-123", "attributes" => { "locale" => "en-US" } },
      { "id" => "loc-de-456", "attributes" => { "locale" => "de-DE" } }
    ]
  end

  before do
    allow(AppStoreConnect::Client).to receive(:new).and_return(mock_client)
    allow(AppStoreConnect::Versions).to receive(:new).and_return(mock_versions_service)
    # The controller fetches localizations to verify the ID belongs to this version
    allow(mock_versions_service).to receive(:localizations)
      .with(version_id: "v-123456")
      .and_return(ownership_check_localizations)
  end

  describe "GET /api/v1/organizations/:organization_id/app_store_versions/:app_store_version_id/localizations" do
    let(:localizations_response) do
      [
        {
          "id" => "loc-en-123",
          "attributes" => {
            "locale" => "en-US",
            "whatsNew" => "Bug fixes and improvements",
            "marketingUrl" => "https://example.com/marketing",
            "promotionalText" => "The best app ever!",
            "supportUrl" => "https://example.com/support"
          }
        },
        {
          "id" => "loc-de-456",
          "attributes" => {
            "locale" => "de-DE",
            "whatsNew" => "Fehlerbehebungen und Verbesserungen",
            "supportUrl" => "https://example.com/support-de"
          }
        }
      ]
    end

    it "returns all localizations for the version" do
      allow(mock_versions_service).to receive(:localizations)
        .with(version_id: app_store_version.version_id)
        .and_return(localizations_response)

      get "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/localizations",
          headers: headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)

      expect(json["data"]["localizations"]).to be_an(Array)
      expect(json["data"]["localizations"].length).to eq(2)

      en_loc = json["data"]["localizations"].find { |l| l["locale"] == "en-US" }
      expect(en_loc["id"]).to eq("loc-en-123")
      expect(en_loc["whats_new"]).to eq("Bug fixes and improvements")
      expect(en_loc["marketing_url"]).to eq("https://example.com/marketing")
      expect(en_loc["promotional_text"]).to eq("The best app ever!")
      expect(en_loc["support_url"]).to eq("https://example.com/support")
    end

    it "returns 404 for non-existent version" do
      get "/api/v1/organizations/#{organization.id}/app_store_versions/999999/localizations",
          headers: headers

      expect(response).to have_http_status(:not_found)
    end

    context "without active credential" do
      before do
        credential.update!(active: false)
      end

      it "returns configuration_required error" do
        get "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/localizations",
            headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("credentials_required")
      end
    end
  end

  describe "POST /api/v1/organizations/:organization_id/app_store_versions/:app_store_version_id/localizations" do
    let(:created_localization) do
      {
        "data" => {
          "id" => "loc-new-789",
          "attributes" => {
            "locale" => "fr-FR",
            "whatsNew" => "Corrections de bogues",
            "marketingUrl" => "https://example.com/fr",
            "supportUrl" => "https://example.com/support-fr"
          }
        }
      }
    end

    it "creates a new localization" do
      allow(mock_versions_service).to receive(:create_localization)
        .with(
          version_id: app_store_version.version_id,
          locale: "fr-FR",
          description: nil,
          keywords: nil,
          whats_new: "Corrections de bogues",
          marketing_url: "https://example.com/fr",
          promotional_text: nil,
          support_url: "https://example.com/support-fr"
        )
        .and_return(created_localization)

      post "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/localizations",
           params: {
             locale: "fr-FR",
             whats_new: "Corrections de bogues",
             marketing_url: "https://example.com/fr",
             support_url: "https://example.com/support-fr"
           }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["message"]).to eq("Localization created successfully")
      expect(json["data"]["locale"]).to eq("fr-FR")
    end

    it "uses default locale en-US when not provided" do
      allow(mock_versions_service).to receive(:create_localization)
        .with(
          version_id: app_store_version.version_id,
          locale: "en-US",
          description: nil,
          keywords: nil,
          whats_new: "Bug fixes",
          marketing_url: nil,
          promotional_text: nil,
          support_url: nil
        )
        .and_return({
          "data" => {
            "id" => "loc-en-new",
            "attributes" => {
              "locale" => "en-US",
              "whatsNew" => "Bug fixes"
            }
          }
        })

      post "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/localizations",
           params: { whats_new: "Bug fixes" }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
    end

    it "normalizes empty strings to nil" do
      allow(mock_versions_service).to receive(:create_localization)
        .with(
          version_id: app_store_version.version_id,
          locale: "en-US",
          description: nil,
          keywords: nil,
          whats_new: "Bug fixes",
          marketing_url: nil,
          promotional_text: nil,
          support_url: nil
        )
        .and_return({
          "data" => {
            "id" => "loc-en-new",
            "attributes" => {
              "locale" => "en-US",
              "whatsNew" => "Bug fixes"
            }
          }
        })

      post "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/localizations",
           params: { whats_new: "Bug fixes", marketing_url: "   ", support_url: "" }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
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
        post "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/localizations",
             params: { whats_new: "Test" }.to_json,
             headers: read_headers

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /api/v1/organizations/:organization_id/app_store_versions/:app_store_version_id/localizations/:id" do
    let(:localization_id) { "loc-en-123" }

    let(:updated_localization) do
      {
        "data" => {
          "id" => localization_id,
          "attributes" => {
            "locale" => "en-US",
            "whatsNew" => "Updated release notes",
            "marketingUrl" => "https://example.com/new-marketing"
          }
        }
      }
    end

    it "updates an existing localization" do
      allow(mock_versions_service).to receive(:update_localization)
        .with(
          localization_id: localization_id,
          description: nil,
          keywords: nil,
          whats_new: "Updated release notes",
          marketing_url: "https://example.com/new-marketing",
          promotional_text: nil,
          support_url: nil
        )
        .and_return(updated_localization)

      patch "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/localizations/#{localization_id}",
            params: {
              whats_new: "Updated release notes",
              marketing_url: "https://example.com/new-marketing"
            }.to_json,
            headers: headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["message"]).to eq("Localization updated successfully")
      expect(json["data"]["whats_new"]).to eq("Updated release notes")
    end

    it "handles Apple API errors" do
      allow(mock_versions_service).to receive(:update_localization)
        .and_raise(StandardError.new("Apple API error"))

      patch "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/localizations/#{localization_id}",
            params: { whats_new: "Test" }.to_json,
            headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("operation_failed")
    end
  end

  describe "DELETE /api/v1/organizations/:organization_id/app_store_versions/:app_store_version_id/localizations/:id" do
    let(:localization_id) { "loc-de-456" }

    it "deletes a localization" do
      allow(mock_client).to receive(:delete)
        .with("appStoreVersionLocalizations/#{localization_id}")
        .and_return(nil)

      delete "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/localizations/#{localization_id}",
             headers: headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["message"]).to eq("Localization deleted successfully")
    end

    it "handles deletion errors" do
      allow(mock_client).to receive(:delete)
        .and_raise(StandardError.new("Cannot delete primary localization"))

      delete "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/localizations/#{localization_id}",
             headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("operation_failed")
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

      it "rejects delete operations" do
        delete "/api/v1/organizations/#{organization.id}/app_store_versions/#{app_store_version.id}/localizations/#{localization_id}",
               headers: read_headers

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
