require "rails_helper"
require "webmock/rspec"

RSpec.describe "Adding an Apple connection", type: :request do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let(:signing_key) { OpenSSL::PKey::EC.generate("prime256v1") }
  let(:connection_params) do
    {
      app_store_connect_credential: {
        name: "Production Apple",
        key_id: "APPLEKEY01",
        issuer_id: "11111111-2222-3333-4444-555555555555",
        private_key: signing_key.to_pem
      }
    }
  end

  before { sign_in user }

  it "validates the submitted key over HTTP before saving and queuing a sync" do
    apple_request = stub_request(:get, "https://api.appstoreconnect.apple.com/v1/bundleIds")
      .with(query: { "limit" => "1", "fields[bundleIds]" => "seedId" })
      .with do |request|
        token = request.headers.fetch("Authorization").delete_prefix("Bearer ")
        claims, headers = JWT.decode(token, signing_key, true, algorithm: "ES256")
        headers["kid"] == "APPLEKEY01" &&
          claims["iss"] == connection_params[:app_store_connect_credential][:issuer_id] &&
          claims["aud"] == "appstoreconnect-v1"
      end
      .to_return(status: 200, body: {
        data: [ { type: "bundleIds", id: "bundle-1", attributes: { seedId: "TEAM12345X" } } ]
      }.to_json, headers: { "Content-Type" => "application/json" })

    expect {
      post organization_app_store_connect_credentials_path(organization), params: connection_params
    }.to change(AppStoreConnectCredential, :count).by(1)
      .and have_enqueued_job(AppStoreConnectSyncJob).with(organization.id)

    expect(apple_request).to have_been_requested.once
    credential = organization.app_store_connect_credentials.sole
    expect(credential).to be_active
    expect(credential.team_id).to eq("TEAM12345X")
    expect(credential.private_key).to eq(signing_key.to_pem.strip)
    follow_redirect!
    expect(response.body).to include("Production Apple", "validated successfully")
  end

  it "explains an Apple agreement failure without saving a connection or queuing a sync" do
    stub_request(:get, %r{https://api\.appstoreconnect\.apple\.com/v1/(bundleIds|apps|certificates)\?})
      .to_return(status: 403, body: {
        errors: [ { title: "Forbidden", detail: "A required agreement is missing or has expired." } ]
      }.to_json, headers: { "Content-Type" => "application/json" })

    expect {
      post organization_app_store_connect_credentials_path(organization), params: connection_params
    }.not_to change(AppStoreConnectCredential, :count)

    expect(AppStoreConnectSyncJob).not_to have_been_enqueued
    expect(flash[:alert]).to include("Account Holder", "agreement")
    expect(flash[:alert]).not_to include("regenerate")
  end

  it "handles missing key fields without a server error" do
    connection_params[:app_store_connect_credential][:key_id] = ""

    expect {
      post organization_app_store_connect_credentials_path(organization), params: connection_params
    }.not_to change(AppStoreConnectCredential, :count)

    expect(response).to redirect_to(organization)
    expect(flash[:alert]).to include("Check the Key ID")
  end

  it "tests an inactive saved key without activating it or starting a sync" do
    credential = create(:app_store_connect_credential, organization: organization,
      active: false, private_key: signing_key.to_pem)
    apple_request = stub_request(:get, "https://api.appstoreconnect.apple.com/v1/certificates")
      .with(query: { "limit" => "1" }).to_return(status: 200, body: { data: [] }.to_json)

    post test_organization_app_store_connect_credential_path(organization, credential)

    expect(flash[:notice]).to eq("Connection successful")
    expect(apple_request).to have_been_requested.once
    expect(credential.reload).not_to be_active
    expect(AppStoreConnectSyncJob).not_to have_been_enqueued
    expect { AppStoreConnect::Client.new(credential: credential) }.to raise_error("Credential inactive")
  end
end
