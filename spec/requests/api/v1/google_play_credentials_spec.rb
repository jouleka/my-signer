require "rails_helper"

RSpec.describe "Api::V1::GooglePlayCredentials", type: :request do
  let!(:user) { User.create!(email: "dev@example.com", password: "SecurePassword123!", confirmed_at: Time.current) }
  let!(:organization) { Organization.create!(name: "Test Org", owner: user) }
  let!(:token_record) { ApiToken.generate_for(user: user, organization: organization, name: "Test Token", scopes: [ "read", "write" ]) }
  let(:api_token) { token_record[1] }
  let(:fake_service_account_json) do
    {
      type: "service_account",
      project_id: "p",
      private_key: SpecCredentialFixtures.pem(body: "abc"),
      client_email: "svc@example.com",
      client_id: "123"
    }.to_json
  end

  let(:headers) do
    {
      "Authorization" => "Bearer #{api_token}",
      "X-User-Email"  => user.email,
      "Content-Type"  => "application/json"
    }
  end

  describe "GET /api/v1/organizations/:organization_id/google_play_credentials" do
    it "lists credentials for the organization" do
      GooglePlayCredential.create!(organization: organization, name: "Default", service_account_json: fake_service_account_json, active: true)

      get "/api/v1/organizations/#{organization.id}/google_play_credentials", headers: headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["google_play_credentials"]).to be_an(Array)
      expect(json["google_play_credentials"].length).to eq(1)
      expect(json["google_play_credentials"][0]["name"]).to eq("Default")
    end
  end

  describe "POST /api/v1/organizations/:organization_id/google_play_credentials" do
    let(:valid_params) do
      {
        google_play_credential: {
          name: "Primary",
          service_account_json: {
            type: "service_account",
            project_id: "proj",
            private_key: SpecCredentialFixtures.pem(body: "abc"),
            client_email: "svc@example.com",
            client_id: "123"
          }.to_json,
          developer_account_id: "123456789",
          active: true
        }
      }
    end
    let(:valid_params_without_active) do
      {
        google_play_credential: valid_params.fetch(:google_play_credential).except(:active)
      }
    end

    it "creates a credential" do
      expect {
        post "/api/v1/organizations/#{organization.id}/google_play_credentials",
             params: valid_params.to_json,
             headers: headers
      }.to change(GooglePlayCredential, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["name"]).to eq("Primary")
      expect(json["developer_account_id"]).to eq("123456789")
    end

    it "emits an AuditEvent on create (mysigner-30)" do
      expect {
        post "/api/v1/organizations/#{organization.id}/google_play_credentials",
             params: valid_params.to_json,
             headers: headers
      }.to change(AuditEvent.where(organization: organization, action: "google_play_credential_added"), :count).by(1)

      event = AuditEvent.where(organization: organization, action: "google_play_credential_added").last
      expect(event.actor).to eq(user)
      expect(event.metadata).to include(
        "credential_id" => GooglePlayCredential.last.id,
        "developer_account_id" => "123456789"
      )
    end

    it "auto-activates the first credential when active is omitted" do
      post "/api/v1/organizations/#{organization.id}/google_play_credentials",
           params: valid_params_without_active.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      credential = organization.google_play_credentials.order(created_at: :desc).first
      expect(credential.active).to eq(true)
      expect(organization.google_play_credentials.where(active: true).pluck(:id)).to eq([ credential.id ])
    end

    it "activates exclusively when active: true" do
      GooglePlayCredential.create!(organization: organization, name: "OldActive", service_account_json: fake_service_account_json, active: true)

      post "/api/v1/organizations/#{organization.id}/google_play_credentials",
           params: valid_params.to_json,
           headers: headers

      expect(response).to have_http_status(:created)

      expect(organization.google_play_credentials.where(active: true).count).to eq(1)
      expect(organization.google_play_credentials.order(created_at: :desc).first.active).to eq(true)
    end

    it "enqueues the initial sync when the credential is activated on create" do
      expect {
        post "/api/v1/organizations/#{organization.id}/google_play_credentials",
             params: valid_params.to_json,
             headers: headers
      }.to have_enqueued_job(GooglePlaySyncJob).with(organization.id)
    end

    it "enqueues the initial sync for paid plans when the credential is activated on create" do
      user.update!(plan_tier: :pro)

      expect {
        post "/api/v1/organizations/#{organization.id}/google_play_credentials",
             params: valid_params_without_active.to_json,
             headers: headers
      }.to have_enqueued_job(GooglePlaySyncJob).with(organization.id)
    end
  end

  describe "DELETE /api/v1/organizations/:organization_id/google_play_credentials/:id" do
    it "deletes a credential" do
      cred = GooglePlayCredential.create!(organization: organization, name: "ToDel", service_account_json: fake_service_account_json, active: false)

      expect {
        delete "/api/v1/organizations/#{organization.id}/google_play_credentials/#{cred.id}", headers: headers
      }.to change(GooglePlayCredential, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/organizations/:organization_id/google_play_credentials/:id/activate" do
    it "sets the given credential active exclusively" do
      old = GooglePlayCredential.create!(organization: organization, name: "Old", service_account_json: fake_service_account_json, developer_account_id: nil, active: true)
      newc = GooglePlayCredential.create!(organization: organization, name: "New", service_account_json: fake_service_account_json, developer_account_id: nil, active: false)

      post "/api/v1/organizations/#{organization.id}/google_play_credentials/#{newc.id}/activate", headers: headers

      expect(response).to have_http_status(:ok)
      expect(organization.google_play_credentials.where(active: true).pluck(:id)).to eq([ newc.id ])
    end

    it "requires write scope" do
      token_record[0].update!(scopes: "read")
      old = GooglePlayCredential.create!(organization: organization, name: "Old", service_account_json: fake_service_account_json, developer_account_id: nil, active: true)
      newc = GooglePlayCredential.create!(organization: organization, name: "New", service_account_json: fake_service_account_json, developer_account_id: nil, active: false)

      post "/api/v1/organizations/#{organization.id}/google_play_credentials/#{newc.id}/activate", headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["error"]).to eq("insufficient_scope")
      expect(organization.google_play_credentials.where(active: true).pluck(:id)).to eq([ old.id ])
    end

    it "enqueues the initial sync for paid plans" do
      user.update!(plan_tier: :pro)
      GooglePlayCredential.create!(organization: organization, name: "Old", service_account_json: fake_service_account_json, developer_account_id: nil, active: true)
      newc = GooglePlayCredential.create!(organization: organization, name: "New", service_account_json: fake_service_account_json, developer_account_id: nil, active: false)

      expect {
        post "/api/v1/organizations/#{organization.id}/google_play_credentials/#{newc.id}/activate", headers: headers
      }.to have_enqueued_job(GooglePlaySyncJob).with(organization.id)
    end
  end

  describe "POST /api/v1/organizations/:organization_id/google_play_credentials/:id/test" do
    it "returns ok when ping works" do
      cred = GooglePlayCredential.create!(organization: organization, name: "T", service_account_json: fake_service_account_json, active: true)

      client_double = instance_double(GooglePlay::Client)
      allow(GooglePlay::Client).to receive(:new).and_return(client_double)
      allow(client_double).to receive(:ping!).and_return(true)

      post "/api/v1/organizations/#{organization.id}/google_play_credentials/#{cred.id}/test", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "returns error when ping raises" do
      cred = GooglePlayCredential.create!(organization: organization, name: "T", service_account_json: fake_service_account_json, active: true)

      client_double = instance_double(GooglePlay::Client)
      allow(GooglePlay::Client).to receive(:new).and_return(client_double)
      allow(client_double).to receive(:ping!).and_raise("boom")

      post "/api/v1/organizations/#{organization.id}/google_play_credentials/#{cred.id}/test", headers: headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "requires write scope" do
      token_record[0].update!(scopes: "read")
      cred = GooglePlayCredential.create!(organization: organization, name: "T", service_account_json: fake_service_account_json, active: true)

      post "/api/v1/organizations/#{organization.id}/google_play_credentials/#{cred.id}/test", headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["error"]).to eq("insufficient_scope")
    end
  end
end
