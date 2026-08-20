require "rails_helper"

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
end
