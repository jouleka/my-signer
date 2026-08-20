require "rails_helper"

RSpec.describe "AppStoreConnectCredentialsController", type: :request do
  let(:user) { create(:user, plan_tier:) }
  let(:organization) { create(:organization, owner: user) }
  let(:plan_tier) { :free }
  let(:private_key) { OpenSSL::PKey::EC.generate("prime256v1").to_pem }
  let(:credential_params) do
    {
      app_store_connect_credential: {
        name: "Primary",
        key_id: "KEY12345",
        issuer_id: "11111111-1111-1111-1111-111111111111",
        private_key: private_key
      }
    }
  end

  before do
    sign_in user, scope: :user

    validation_result = AppStoreConnect::CredentialValidator::Result.new(
      team_id: "TEAM12345",
      sources: [],
      raw_samples: {}
    )
    validator_double = instance_double(AppStoreConnect::CredentialValidator, validate!: validation_result)

    allow(AppStoreConnect::CredentialValidator).to receive(:new).and_return(validator_double)
  end

  it "enqueues the initial sync for free plans" do
    expect {
      post organization_app_store_connect_credentials_path(organization), params: credential_params
    }.to have_enqueued_job(AppStoreConnectSyncJob).with(organization.id)

    expect(flash[:notice]).to eq("Credential added and validated successfully. Team ID: TEAM12345. Syncing...")
  end

  it "enqueues the initial sync for paid plans" do
    user.update!(plan_tier: :pro)

    expect {
      post organization_app_store_connect_credentials_path(organization), params: credential_params
    }.to have_enqueued_job(AppStoreConnectSyncJob).with(organization.id)

    expect(flash[:notice]).to eq("Credential added and validated successfully. Team ID: TEAM12345. Syncing...")
  end

  it "enqueues sync on activation for free plans" do
    credential = organization.app_store_connect_credentials.create!(
      name: "Inactive",
      key_id: "KEY99999",
      issuer_id: "22222222-2222-2222-2222-222222222222",
      private_key: private_key,
      team_id: "TEAM12345",
      active: false
    )

    expect {
      post activate_organization_app_store_connect_credential_path(organization, credential)
    }.to have_enqueued_job(AppStoreConnectSyncJob).with(organization.id)

    expect(flash[:notice]).to eq("Credential set active. Syncing...")
  end

  it "enqueues sync on activation for paid plans" do
    user.update!(plan_tier: :pro)
    credential = organization.app_store_connect_credentials.create!(
      name: "Inactive",
      key_id: "KEY99999",
      issuer_id: "22222222-2222-2222-2222-222222222222",
      private_key: private_key,
      team_id: "TEAM12345",
      active: false
    )

    expect {
      post activate_organization_app_store_connect_credential_path(organization, credential)
    }.to have_enqueued_job(AppStoreConnectSyncJob).with(organization.id)

    expect(flash[:notice]).to eq("Credential set active. Syncing...")
  end

  context "when validation fails" do
    let(:probe_class) { AppStoreConnect::CredentialValidator::Probe }
    let(:failing_trace) do
      [
        probe_class.new(endpoint: "bundleIds",    outcome: :denied, status: 403),
        probe_class.new(endpoint: "apps",         outcome: :empty,  status: 200, data_count: 0),
        probe_class.new(endpoint: "certificates", outcome: :denied, status: 403)
      ]
    end

    before do
      validator_double = instance_double(AppStoreConnect::CredentialValidator)
      allow(AppStoreConnect::CredentialValidator).to receive(:new).and_return(validator_double)
      allow(validator_double).to receive(:validate!).and_raise(
        AppStoreConnect::CredentialValidator::ValidationError.new(
          "Your API key was denied access to some resources and returned no data on others.",
          trace: failing_trace
        )
      )
    end

    it "redirects with an alert and creates no credential row" do
      expect {
        post organization_app_store_connect_credentials_path(organization), params: credential_params
      }.not_to change(AppStoreConnectCredential, :count)

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include("Apple validation failed")
      expect(flash[:alert]).to include("denied access")
    end

    it "records an asc_credential_validation_failed audit event with the trace" do
      expect {
        post organization_app_store_connect_credentials_path(organization), params: credential_params
      }.to change(AuditEvent, :count).by(1)

      event = AuditEvent.last
      expect(event.action).to eq("asc_credential_validation_failed")
      expect(event.organization_id).to eq(organization.id)
      expect(event.actor_id).to eq(user.id)

      # key_id_suffix is the last 4 chars only — not the full key_id
      expect(event.metadata["key_id_suffix"]).to eq("2345")
      expect(event.metadata["key_id_suffix"]).not_to include("KEY1")

      trace = event.metadata["trace"]
      expect(trace).to be_an(Array)
      expect(trace.size).to eq(3)
      expect(trace.map { |t| t["endpoint"] }).to eq([ "bundleIds", "apps", "certificates" ])
      expect(trace.map { |t| t["outcome"] }).to eq([ "denied", "empty", "denied" ])
      expect(trace.map { |t| t["status"] }).to eq([ 403, 200, 403 ])
    end
  end
end
