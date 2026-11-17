require "rails_helper"
require "webmock/rspec"

RSpec.describe "GooglePlayCredentialsController", type: :request do
  let(:user) { create(:user, plan_tier:) }
  let(:organization) { create(:organization, owner: user) }
  let(:plan_tier) { :free }
  let(:credential_params) do
    {
      google_play_credential: {
        name: "Primary",
        service_account_json: {
          type: "service_account",
          project_id: "proj",
          private_key: "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n",
          client_email: "svc@example.com",
          client_id: "123"
        }.to_json,
        developer_account_id: "123456789"
      }
    }
  end

  before do
    sign_in user, scope: :user
  end

  [ "[]", "null", "true", "123", '"not an object"' ].each do |json|
    it "rejects #{json} without saving or crashing" do
      credential_params[:google_play_credential][:service_account_json] = json

      expect {
        post organization_google_play_credentials_path(organization), params: credential_params
      }.not_to change(GooglePlayCredential, :count)

      expect(response).to redirect_to(organization_path(organization))
      expect(flash[:alert]).to include("must be a JSON object")
    end
  end

  it "enqueues the initial sync for free plans" do
    expect {
      post organization_google_play_credentials_path(organization), params: credential_params
    }.to have_enqueued_job(GooglePlaySyncJob).with(organization.id)

    expect(flash[:notice]).to eq("Google Play credential added. Syncing...")
  end

  it "enqueues the initial sync for paid plans" do
    user.update!(plan_tier: :pro)

    expect {
      post organization_google_play_credentials_path(organization), params: credential_params
    }.to have_enqueued_job(GooglePlaySyncJob).with(organization.id)
  end

  it "enqueues sync on activation for free plans" do
    credential = organization.google_play_credentials.create!(
      name: "Inactive",
      service_account_json: credential_params.dig(:google_play_credential, :service_account_json),
      developer_account_id: "123456789",
      active: false
    )

    expect {
      post activate_organization_google_play_credential_path(organization, credential)
    }.to have_enqueued_job(GooglePlaySyncJob).with(organization.id)

    expect(flash[:notice]).to eq("Google Play credential set active. Syncing...")
  end

  it "keeps the syncing notice when a paid activation actually enqueues a sync" do
    user.update!(plan_tier: :pro)
    credential = organization.google_play_credentials.create!(
      name: "Inactive",
      service_account_json: credential_params.dig(:google_play_credential, :service_account_json),
      developer_account_id: "123456789",
      active: false
    )

    expect {
      post activate_organization_google_play_credential_path(organization, credential)
    }.to have_enqueued_job(GooglePlaySyncJob).with(organization.id)

    expect(flash[:notice]).to eq("Google Play credential set active. Syncing...")
  end

  it "tests an inactive credential without changing the active connection" do
    json = JSON.parse(credential_params[:google_play_credential][:service_account_json])
    json["private_key"] = OpenSSL::PKey::RSA.generate(2048).to_pem
    credential = create(:google_play_credential, organization: organization, active: false,
      service_account_json: json.to_json)
    token_request = stub_request(:post, "https://www.googleapis.com/oauth2/v4/token")
      .to_return(status: 200, body: { access_token: "qa-only-token", token_type: "Bearer", expires_in: 3600 }.to_json,
        headers: { "Content-Type" => "application/json" })

    post test_organization_google_play_credential_path(organization, credential)

    expect(flash[:notice]).to eq("Google Play connection successful")
    expect(token_request).to have_been_requested.once
    expect(credential.reload).not_to be_active
    expect(GooglePlaySyncJob).not_to have_been_enqueued
    expect { GooglePlay::Client.new(credential: credential) }.to raise_error("Credential inactive")
  end
end
