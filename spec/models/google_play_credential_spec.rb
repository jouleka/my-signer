require "rails_helper"

RSpec.describe GooglePlayCredential, type: :model do
  let(:user) { User.create!(email: "gpcred@example.com", password: "SecurePass123!", confirmed_at: Time.current) }
  let(:organization) { Organization.create!(name: "Org", owner: user) }

  let(:service_account_json) do
    {
      type: "service_account",
      project_id: "my-gcp-project",
      private_key: "-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----\n",
      client_email: "sa@my-gcp-project.iam.gserviceaccount.com",
      client_id: "112233"
    }.to_json
  end

  subject(:credential) do
    described_class.create!(
      organization: organization,
      name: "Test GP",
      service_account_json: service_account_json,
      active: true
    )
  end

  describe "#project_id" do
    it "extracts project_id from the service_account_json" do
      expect(credential.project_id).to eq("my-gcp-project")
    end

    it "returns nil when the JSON is malformed" do
      # Force a malformed plaintext on the in-memory accessor and bypass the
      # JSON-structure validation. Post-mysigner-32 the AR column is no longer
      # the source of truth, so we can't simulate corruption by writing to it
      # directly — the accessor would read the (still-valid) envelope. Instead
      # we drive plaintext through the public setter, which #project_id reads
      # in this object's lifetime without going back to the envelope.
      credential.service_account_json = "{ not valid json"
      credential.save!(validate: false)
      expect(credential.project_id).to be_nil
    end
  end

  describe "#play_reporting_api_enable_url" do
    it "returns the Google Cloud Console URL scoped to the project" do
      expect(credential.play_reporting_api_enable_url).to eq(
        "https://console.developers.google.com/apis/api/playdeveloperreporting.googleapis.com/overview?project=my-gcp-project"
      )
    end

    it "returns nil when project_id cannot be determined" do
      # Same approach as the malformed-JSON case in #project_id — drive
      # plaintext through the in-memory accessor and skip JSON validation.
      credential.service_account_json = "{ not valid json"
      credential.save!(validate: false)
      expect(credential.play_reporting_api_enable_url).to be_nil
    end
  end

  describe "#play_reporting_api_disabled?" do
    it "is false by default" do
      expect(credential.play_reporting_api_disabled?).to be false
    end

    it "is true after mark_play_reporting_api_disabled!" do
      credential.mark_play_reporting_api_disabled!
      expect(credential.play_reporting_api_disabled?).to be true
      expect(credential.play_reporting_api_disabled_at).to be_within(5.seconds).of(Time.current)
    end
  end

  describe "#mark_play_reporting_api_disabled!" do
    it "stamps the timestamp only on first detection" do
      credential.mark_play_reporting_api_disabled!
      first_stamp = credential.reload.play_reporting_api_disabled_at

      # A second call must not overwrite the original stamp — otherwise
      # a sync storm would make the banner lie about "detected N ago".
      credential.mark_play_reporting_api_disabled!
      expect(credential.reload.play_reporting_api_disabled_at).to eq(first_stamp)
    end
  end

  describe "#mark_play_reporting_api_enabled!" do
    it "clears the timestamp when previously disabled" do
      credential.mark_play_reporting_api_disabled!
      credential.mark_play_reporting_api_enabled!
      expect(credential.reload.play_reporting_api_disabled_at).to be_nil
    end

    it "is a no-op when already enabled (avoids an UPDATE per sync)" do
      expect {
        credential.mark_play_reporting_api_enabled!
      }.not_to change { credential.reload.updated_at }
    end
  end

  describe "#mark_sync_failure! sanitization" do
    it "redacts PEM before persisting" do
      credential.mark_sync_failure!("-----BEGIN EC PRIVATE KEY-----\nX\n-----END EC PRIVATE KEY-----")
      expect(credential.reload.last_sync_error).to include("[REDACTED_PEM]")
    end
  end

  describe "cache invalidation" do
    before do
      @store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(@store)
    end

    let(:cred) { create(:google_play_credential, service_account_json: service_account_json) }
    before { Rails.cache.write("gp_access_token:#{cred.id}", "cached-token-value", expires_in: 55.minutes) }

    it "purges cached token on service_account_json update" do
      new_json = cred.service_account_json.sub("my-gcp-project", "prod-gcp-project")
      cred.update!(service_account_json: new_json)
      expect(Rails.cache.read("gp_access_token:#{cred.id}")).to be_nil
    end

    it "purges cached token on destroy" do
      id = cred.id
      cred.destroy!
      expect(Rails.cache.read("gp_access_token:#{id}")).to be_nil
    end

    it "does NOT purge on unrelated field update" do
      cred.update!(name: "new name")
      expect(Rails.cache.read("gp_access_token:#{cred.id}")).to eq("cached-token-value")
    end
  end

  describe "Vaulted service_account_json (mysigner-26)" do
    let(:kms)                 { instance_double(Aws::KMS::Client) }
    let(:plaintext_dek)       { OpenSSL::Random.random_bytes(32) }
    let(:wrapped_dek)         { "wrapped-#{SecureRandom.hex(16)}".b }
    let(:returned_kms_key_id) { "arn:aws:kms:us-east-1:0:key/test" }

    before do
      CredentialVault.kms_client = kms
      CredentialVault.key_arn    = returned_kms_key_id
      allow(kms).to receive(:generate_data_key).and_return(
        double("GDK", plaintext: plaintext_dek, ciphertext_blob: wrapped_dek, key_id: returned_kms_key_id)
      )
      allow(kms).to receive(:decrypt).and_return(
        double("DKR", plaintext: plaintext_dek, key_id: returned_kms_key_id)
      )
      Rails.cache.clear
    end

    after do
      CredentialVault.kms_client = nil
      CredentialVault.key_arn    = nil
    end

    it "populates service_account_json_envelope on create with a roundtrip-decryptable envelope" do
      cred = create(:google_play_credential, service_account_json: service_account_json)
      cred.reload

      expect(cred.service_account_json_envelope).to be_present

      envelope = CredentialVault.unpack(cred.service_account_json_envelope)
      decrypted = CredentialVault.decrypt(envelope, context: {
        org_id:          cred.organization_id.to_s,
        credential_kind: "google_play",
        credential_id:   cred.vault_record_id
      })
      expect(decrypted).to eq(service_account_json)
    end

    it "re-encrypts envelope when service_account_json changes" do
      cred = create(:google_play_credential, service_account_json: service_account_json)
      initial_envelope = cred.service_account_json_envelope

      rotated = service_account_json.sub("my-gcp-project", "prod-gcp-project")
      cred.update!(service_account_json: rotated)

      expect(cred.service_account_json_envelope).to be_present
      expect(cred.service_account_json_envelope).not_to eq(initial_envelope)
    end

    it "skips KMS round-trip when service_account_json did NOT change" do
      cred = create(:google_play_credential, service_account_json: service_account_json)
      expect(kms).to have_received(:generate_data_key).once

      cred.update!(name: "renamed")
      expect(kms).to have_received(:generate_data_key).once
    end

    it "binds the envelope to vault_record_id (swap-attack defense)" do
      cred_a = create(:google_play_credential, service_account_json: service_account_json)
      cred_b = create(:google_play_credential,
        service_account_json: service_account_json.sub("my-gcp-project", "other-gcp-project"),
        name: "Other GP")

      cred_a.update_column(:service_account_json_envelope, cred_b.service_account_json_envelope)

      envelope = CredentialVault.unpack(cred_a.reload.service_account_json_envelope)
      expect {
        CredentialVault.decrypt(envelope, context: {
          org_id:          cred_a.organization_id.to_s,
          credential_kind: "google_play",
          credential_id:   cred_a.vault_record_id
        })
      }.to raise_error(CredentialVault::DecryptError)
    end
  end
end
