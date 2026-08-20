require "rails_helper"

RSpec.describe "POST /api/v1/organizations/:id/android_keystores/:id/secrets", type: :request do
  let(:user)   { create(:user) }
  let(:org)    { create(:organization, owner: user) }
  let(:token_pair) { ApiToken.generate_for(user: user, organization: org, name: "t", scopes: %w[read write admin]) }
  let(:plain_token) { token_pair.last }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}", "X-User-Email" => user.email } }

  before do
    validator = instance_double("Android::KeystoreValidator")
    result = instance_double("Android::KeystoreValidator::Result",
      valid_until: 1.year.from_now,
      alias: "alias",
      certificate_subject: "CN=Test",
      certificate_issuer: "CN=Test",
      valid_from: Time.current,
      fingerprints: {}
    )
    allow(validator).to receive(:validate!).and_return(result)
    allow(Android::KeystoreValidator).to receive(:new).and_return(validator)
  end

  let!(:ks) { create(:android_keystore, organization: org, key_alias: "myalias", key_password: "keypw", keystore_password: "storepw") }

  it "returns 200 with passwords + alias" do
    post "/api/v1/organizations/#{org.id}/android_keystores/#{ks.id}/secrets", headers: headers
    expect(response.status).to eq(200)
    body = JSON.parse(response.body)
    expect(body["keystore_password"]).to eq(ks.keystore_password)
    expect(body["key_password"]).to eq(ks.key_password)
    expect(body["key_alias"]).to eq(ks.key_alias)
  end

  it "emits an AuditEvent" do
    expect {
      post "/api/v1/organizations/#{org.id}/android_keystores/#{ks.id}/secrets", headers: headers
    }.to change(AuditEvent.where(action: "credential_read_android_keystore_secrets"), :count).by(1)
  end

  it "is 404 for wrong-org keystore" do
    other_ks = create(:android_keystore)
    post "/api/v1/organizations/#{org.id}/android_keystores/#{other_ks.id}/secrets", headers: headers
    expect(response.status).to eq(404)
  end

  it "is 403 insufficient_scope for a write-only token" do
    pair = ApiToken.generate_for(user: user, organization: org, name: "write-only", scopes: %w[read write])
    write_only_headers = { "Authorization" => "Bearer #{pair.last}", "X-User-Email" => user.email }
    post "/api/v1/organizations/#{org.id}/android_keystores/#{ks.id}/secrets", headers: write_only_headers
    expect(response.status).to eq(403)
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("insufficient_scope")
    expect(body["details"]["required_scope"]).to eq("admin")
  end
end
