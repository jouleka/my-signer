require "rails_helper"

RSpec.describe "POST /api/v1/organizations/:id/credentials/google_play/access_token", type: :request do
  let(:user) { create(:user) }
  let(:org)  { create(:organization, owner: user) }
  let!(:token_record_and_plain) { ApiToken.generate_for(user: user, organization: org, name: "test", scopes: %w[write admin]) }
  let(:plain_token) { token_record_and_plain.last }
  let(:headers) do
    {
      "Authorization" => "Bearer #{plain_token}",
      "X-User-Email"  => user.email,
      "Content-Type"  => "application/json"
    }
  end

  before do
    Rails.cache.clear
    allow(GooglePlay::TokenMinter).to receive(:mint).and_return(
      access_token: "ya29.FAKE",
      expires_at: Time.now + 3600,
      client_email: "pub@x.iam.gserviceaccount.com",
      developer_account_id: nil,
      cache_hit: false
    )
  end

  context "with active credential" do
    let(:valid_sa_json) do
      {
        type: "service_account",
        project_id: "proj",
        private_key: SpecCredentialFixtures.pem(body: "abc"),
        client_email: "svc@example.com",
        client_id: "123"
      }.to_json
    end
    before do
      create(:google_play_credential, organization: org, service_account_json: valid_sa_json, active: true)
    end

    it "returns 200 with token body" do
      post "/api/v1/organizations/#{org.id}/credentials/google_play/access_token", headers: headers
      expect(response.status).to eq(200)
      body = JSON.parse(response.body)
      expect(body["access_token"]).to eq("ya29.FAKE")
      expect(body["client_email"]).to be_present
    end

    it "emits an AuditEvent" do
      expect {
        post "/api/v1/organizations/#{org.id}/credentials/google_play/access_token", headers: headers
      }.to change(AuditEvent.where(action: "credential_read_google_play_token"), :count).by(1)
    end
  end

  context "without active credential" do
    it "returns 404" do
      post "/api/v1/organizations/#{org.id}/credentials/google_play/access_token", headers: headers
      expect(response.status).to eq(404)
    end
  end

  context "with a write-only token (no admin scope)" do
    let!(:valid_sa_json) do
      {
        type: "service_account",
        project_id: "proj",
        private_key: SpecCredentialFixtures.pem(body: "abc"),
        client_email: "svc@example.com",
        client_id: "123"
      }.to_json
    end
    before do
      create(:google_play_credential, organization: org, service_account_json: valid_sa_json, active: true)
    end

    it "returns 403 insufficient_scope" do
      write_only_pair = ApiToken.generate_for(user: user, organization: org, name: "write-only", scopes: %w[read write])
      write_only_headers = {
        "Authorization" => "Bearer #{write_only_pair.last}",
        "X-User-Email"  => user.email,
        "Content-Type"  => "application/json"
      }
      post "/api/v1/organizations/#{org.id}/credentials/google_play/access_token", headers: write_only_headers
      expect(response.status).to eq(403)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("insufficient_scope")
      expect(body["details"]["required_scope"]).to eq("admin")
    end
  end
end
