require "rails_helper"

RSpec.describe "API Sync", type: :request do
  let(:user) { User.create!(email: "u@e.com", password: "QwErTy!12345$", confirmed_at: Time.current) }
  let(:org)  { Organization.create!(name: "Org", owner: user) }

  before do
    # simulate logged-in session for API
    sign_in user, scope: :user
  end

  it "returns 422 when no credentials" do
    post sync_app_store_connect_api_v1_organization_path(org), headers: { "ACCEPT"=>"application/json" }
    expect(response.status).to eq(422)
    expect(JSON.parse(response.body)["error"]).to eq("credentials_required")
  end

  it "enqueues job when creds exist" do
    key = OpenSSL::PKey::EC.generate("prime256v1")
    AppStoreConnectCredential.create!(organization: org, name: "Apple", key_id: "KEY12345", issuer_id: "11111111-1111-1111-1111-111111111111", private_key: key.to_pem, active: true)

    expect {
      post sync_app_store_connect_api_v1_organization_path(org), headers: { "ACCEPT"=>"application/json" }
    }.to have_enqueued_job(AppStoreConnectSyncJob).with(org.id)

    expect(response.status).to eq(202)
    body = JSON.parse(response.body)
    expect(body["enqueued"]).to eq(true)
  end
end
