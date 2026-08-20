require "rails_helper"

RSpec.describe "Api::V1::AppStoreConnectCredentials", type: :request do
  let(:user) { User.create!(email: "dev@example.com", password: "SecurePassword123!", confirmed_at: Time.current) }
  let(:organization) { Organization.create!(name: "Test Org", owner: user) }
  let(:token_record) { ApiToken.generate_for(user: user, organization: organization, name: "Test Token", scopes: [ "read", "write" ]) }
  let(:api_token) { token_record[1] }

  let(:headers) do
    {
      "Authorization" => "Bearer #{api_token}",
      "X-User-Email" => user.email,
      "Content-Type" => "application/json"
    }
  end

  let(:private_key) { OpenSSL::PKey::EC.generate("prime256v1").to_pem }

  let(:valid_params) do
    {
      app_store_connect_credential: {
        name: "Primary",
        key_id: "ABC12345",
        issuer_id: "11111111-1111-1111-1111-111111111111",
        private_key: private_key
      }
    }
  end

  describe "POST /api/v1/organizations/:organization_id/app_store_connect_credentials" do
    it "validates credentials, stores them, and auto-activates if first credential" do
      validation_result = AppStoreConnect::CredentialValidator::Result.new(
        team_id: "TEAMID123",
        sources: [ "apps" ],
        raw_samples: []
      )

      validator_double = instance_double(AppStoreConnect::CredentialValidator)
      allow(AppStoreConnect::CredentialValidator).to receive(:new)
        .with(hash_including(key_id: "ABC12345", issuer_id: "11111111-1111-1111-1111-111111111111"))
        .and_return(validator_double)
      allow(validator_double).to receive(:validate!).and_return(validation_result)

      expect {
        post "/api/v1/organizations/#{organization.id}/app_store_connect_credentials",
             params: valid_params.to_json,
             headers: headers
      }.to change(AppStoreConnectCredential, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["team_id"]).to eq("TEAMID123")
      expect(json.dig("validation", "success")).to eq(true)
      expect(json.dig("validation", "team_id")).to eq("TEAMID123")

      credential = AppStoreConnectCredential.last
      expect(credential.active).to eq(true) # Auto-activated because it's the first
      expect(credential.team_id).to eq("TEAMID123")
    end

    it "does not auto-activate if not the first credential" do
      # Create first credential
      AppStoreConnectCredential.create!(
        organization: organization,
        name: "Existing",
        key_id: "EXISTING123",
        issuer_id: "22222222-2222-2222-2222-222222222222",
        private_key: OpenSSL::PKey::EC.generate("prime256v1").to_pem,
        active: true
      )

      validation_result = AppStoreConnect::CredentialValidator::Result.new(
        team_id: "TEAMID456",
        sources: [ "apps" ],
        raw_samples: []
      )

      validator_double = instance_double(AppStoreConnect::CredentialValidator)
      allow(AppStoreConnect::CredentialValidator).to receive(:new).and_return(validator_double)
      allow(validator_double).to receive(:validate!).and_return(validation_result)

      post "/api/v1/organizations/#{organization.id}/app_store_connect_credentials",
           params: valid_params.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      credential = AppStoreConnectCredential.last
      expect(credential.active).to eq(false) # Not auto-activated
      expect(credential.team_id).to eq("TEAMID456")
    end

    it "emits an AuditEvent on create (mysigner-30)" do
      validation_result = AppStoreConnect::CredentialValidator::Result.new(
        team_id: "TEAMID789", sources: [ "apps" ], raw_samples: []
      )
      validator_double = instance_double(AppStoreConnect::CredentialValidator)
      allow(AppStoreConnect::CredentialValidator).to receive(:new).and_return(validator_double)
      allow(validator_double).to receive(:validate!).and_return(validation_result)

      expect {
        post "/api/v1/organizations/#{organization.id}/app_store_connect_credentials",
             params: valid_params.to_json,
             headers: headers
      }.to change(AuditEvent.where(organization: organization, action: "asc_credential_added"), :count).by(1)

      event = AuditEvent.where(organization: organization, action: "asc_credential_added").last
      expect(event.actor).to eq(user)
      expect(event.metadata).to include("credential_id" => AppStoreConnectCredential.last.id, "key_id" => "ABC12345")
    end

    it "enqueues the initial sync for free plans" do
      validation_result = AppStoreConnect::CredentialValidator::Result.new(
        team_id: "TEAMID123",
        sources: [ "apps" ],
        raw_samples: []
      )

      validator_double = instance_double(AppStoreConnect::CredentialValidator)
      allow(AppStoreConnect::CredentialValidator).to receive(:new).and_return(validator_double)
      allow(validator_double).to receive(:validate!).and_return(validation_result)

      expect {
        post "/api/v1/organizations/#{organization.id}/app_store_connect_credentials",
             params: valid_params.to_json,
             headers: headers
      }.to have_enqueued_job(AppStoreConnectSyncJob).with(organization.id)
    end

    it "enqueues the initial sync for paid plans when the first credential is created" do
      user.update!(plan_tier: :pro)
      validation_result = AppStoreConnect::CredentialValidator::Result.new(
        team_id: "TEAMID123",
        sources: [ "apps" ],
        raw_samples: []
      )

      validator_double = instance_double(AppStoreConnect::CredentialValidator)
      allow(AppStoreConnect::CredentialValidator).to receive(:new).and_return(validator_double)
      allow(validator_double).to receive(:validate!).and_return(validation_result)

      expect {
        post "/api/v1/organizations/#{organization.id}/app_store_connect_credentials",
             params: valid_params.to_json,
             headers: headers
      }.to have_enqueued_job(AppStoreConnectSyncJob).with(organization.id)
    end

    it "returns validation error when Apple rejects credentials" do
      validator_double = instance_double(AppStoreConnect::CredentialValidator)
      allow(AppStoreConnect::CredentialValidator).to receive(:new).and_return(validator_double)
      allow(validator_double).to receive(:validate!).and_raise(AppStoreConnect::CredentialValidator::ValidationError.new("Invalid key"))

      expect {
        post "/api/v1/organizations/#{organization.id}/app_store_connect_credentials",
             params: valid_params.to_json,
             headers: headers
      }.not_to change(AppStoreConnectCredential, :count)

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("external_error")
    end

    it "requires write scope when using API token" do
      token_record[0].update!(scopes: "read")

      expect {
        post "/api/v1/organizations/#{organization.id}/app_store_connect_credentials",
             params: valid_params.to_json,
             headers: headers
      }.not_to change(AppStoreConnectCredential, :count)

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("insufficient_scope")
    end

    it "rejects token-authenticated request when X-User-Email is missing (mysigner-30)" do
      # WHY: a leaked API token alone must NOT be sufficient to manage
      # credentials. The CLI always sends X-User-Email; a thief without
      # knowledge of the user's email gets 401 even with a valid token.
      headers_without_email = headers.except("X-User-Email")

      expect {
        post "/api/v1/organizations/#{organization.id}/app_store_connect_credentials",
             params: valid_params.to_json,
             headers: headers_without_email
      }.not_to change(AppStoreConnectCredential, :count)

      expect(response).to have_http_status(:unauthorized)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("unauthorized")
      expect(json["message"]).to include("X-User-Email")
    end
  end
end
