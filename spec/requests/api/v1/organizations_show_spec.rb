require "rails_helper"

RSpec.describe "Api::V1::Organizations show", type: :request do
  let(:user) { User.create!(email: "dev@example.com", password: "SecurePassword123!", confirmed_at: Time.current) }
  let(:organization) { Organization.create!(name: "Test Org", owner: user) }
  let(:token_record) { ApiToken.generate_for(user: user, organization: organization, name: "Show Token", scopes: [ "read" ]) }
  let(:api_token) { token_record[1] }

  let(:headers) do
    {
      "Authorization" => "Bearer #{api_token}",
      "X-User-Email" => user.email
    }
  end

  it "returns credentials status flags" do
    AppStoreConnectCredential.create!(
      organization: organization,
      name: "Primary",
      key_id: "KEY12345",
      issuer_id: "11111111-1111-1111-1111-111111111111",
      private_key: OpenSSL::PKey::EC.generate("prime256v1").to_pem,
      team_id: "TEAM12345",
      active: true
    )

    get "/api/v1/organizations/#{organization.id}", headers: headers

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)

    expect(json["credentials_status"]).to eq({
      "configured" => true,
      "team_id_set" => true,
      "needs_setup" => false
    })
    expect(json["plan"]["tier"]).to eq("free")
    expect(json["plan"]["next_tier"]).to eq("pro")
    expect(json["plan"]["entitlements"]["limits"]["owned_organizations"]).to eq(1)
    expect(json["plan"]["entitlements"]["features"]["store_uploads"]).to eq(false)
    expect(json["plan"]["usage"]["media_storage_bytes"]).to eq(0)
    expect(json["plan"]["usage"]["export_storage_bytes"]).to eq(0)
    expect(json["plan"]["usage"]["store_uploads_last_24_hours"]).to eq(0)
  end
end
