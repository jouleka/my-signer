require "rails_helper"

RSpec.describe Organization, type: :model do
  let(:organization) { create(:organization) }
  let(:valid_sa_json) do
    {
      type: "service_account",
      project_id: "test",
      private_key_id: "k1",
      private_key: "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n",
      client_email: "test@test.iam.gserviceaccount.com",
      client_id: "123"
    }.to_json
  end

  describe "#any_active_platform_credential?" do
    it "returns false when no creds exist" do
      expect(organization.any_active_platform_credential?).to be false
    end

    it "returns true when an active ASC cred exists" do
      create(:app_store_connect_credential, organization: organization, active: true)
      expect(organization.any_active_platform_credential?).to be true
    end

    it "returns true when an active Google Play cred exists" do
      create(:google_play_credential, organization: organization, active: true, service_account_json: valid_sa_json)
      expect(organization.any_active_platform_credential?).to be true
    end

    it "returns false when creds exist but all inactive" do
      create(:app_store_connect_credential, organization: organization, active: false)
      create(:google_play_credential, organization: organization, active: false, service_account_json: valid_sa_json)
      expect(organization.any_active_platform_credential?).to be false
    end
  end
end
