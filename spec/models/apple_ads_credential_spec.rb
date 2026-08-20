require "rails_helper"

RSpec.describe AppleAdsCredential, type: :model do
  describe "validations" do
    it "is valid with all required fields" do
      expect(build(:apple_ads_credential)).to be_valid
    end

    it "requires client_id" do
      cred = build(:apple_ads_credential, client_id: nil)
      expect(cred).not_to be_valid
      expect(cred.errors[:client_id]).to include("can't be blank")
    end

    it "requires team_id" do
      cred = build(:apple_ads_credential, team_id: nil)
      expect(cred).not_to be_valid
    end

    it "requires key_id" do
      cred = build(:apple_ads_credential, key_id: nil)
      expect(cred).not_to be_valid
    end

    it "requires private_key_pem" do
      cred = build(:apple_ads_credential, private_key_pem: nil)
      expect(cred).not_to be_valid
    end

    it "rejects client_id longer than 64 chars" do
      expect(build(:apple_ads_credential, client_id: "a" * 65)).not_to be_valid
      expect(build(:apple_ads_credential, client_id: "a" * 64)).to be_valid
    end

    it "rejects team_id longer than 32 chars" do
      expect(build(:apple_ads_credential, team_id: "a" * 33)).not_to be_valid
    end

    it "rejects key_id longer than 32 chars" do
      expect(build(:apple_ads_credential, key_id: "a" * 33)).not_to be_valid
    end

    it "rejects a non-EC private key" do
      fake_rsa = "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA...\n-----END RSA PRIVATE KEY-----"
      cred = build(:apple_ads_credential, private_key_pem: fake_rsa)
      expect(cred).not_to be_valid
      expect(cred.errors[:private_key_pem].join).to match(/EC|valid/i)
    end

    it "rejects a malformed PEM" do
      cred = build(:apple_ads_credential, private_key_pem: "not a pem")
      expect(cred).not_to be_valid
    end

    it "enforces one-per-organization uniqueness at DB level" do
      org = create(:organization)
      create(:apple_ads_credential, organization: org)
      expect { create(:apple_ads_credential, organization: org) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "encryption" do
    it "encrypts client_id, team_id, key_id via Rails AR Encryption at rest" do
      # client_id/team_id/key_id are still Rails-AR-encrypted (identifiers,
      # not signing material, must remain queryable by deterministic AR
      # encryption). The raw DB column for these MUST be ciphertext, not the
      # plaintext value the model exposes.
      cred = create(:apple_ads_credential)
      row = ActiveRecord::Base.connection.select_one(
        "SELECT client_id, team_id, key_id FROM apple_ads_credentials WHERE id = #{cred.id}"
      )
      expect(row["client_id"]).not_to eq(cred.client_id)
      expect(row["team_id"]).not_to eq(cred.team_id)
      expect(row["key_id"]).not_to eq(cred.key_id)
    end

    it "encrypts private_key_pem via the envelope column (mysigner-32)" do
      # private_key_pem is the actual signing material. After mysigner-33 the
      # legacy AR column is GONE; the only at-rest storage for the PEM is
      # the KMS-wrapped envelope. This spec locks down two properties:
      #   1. The envelope column holds ciphertext, not the PEM verbatim.
      #   2. The model accessor decrypts back to the original plaintext.
      cred = create(:apple_ads_credential)
      row = ActiveRecord::Base.connection.select_one(
        "SELECT private_key_pem_envelope FROM apple_ads_credentials WHERE id = #{cred.id}"
      )
      # Envelope holds the KMS-wrapped ciphertext — never the PEM verbatim.
      expect(row["private_key_pem_envelope"]).to be_present
      expect(row["private_key_pem_envelope"]).not_to include("BEGIN EC PRIVATE KEY")
      # And the public accessor decrypts back to the plaintext PEM.
      expect(cred.private_key_pem).to include("BEGIN EC PRIVATE KEY")
    end
  end

  describe "#last_successful?" do
    it "returns true when last_successful_at is set" do
      expect(build(:apple_ads_credential, last_successful_at: Time.current).last_successful?).to be true
    end

    it "returns false when last_successful_at is nil" do
      expect(build(:apple_ads_credential, last_successful_at: nil).last_successful?).to be false
    end
  end

  describe "#mark_success!" do
    it "sets last_successful_at and clears last_error" do
      cred = create(:apple_ads_credential, last_error: "old error")
      cred.mark_success!
      expect(cred.last_successful_at).to be_within(2.seconds).of(Time.current)
      expect(cred.last_error).to be_nil
    end
  end

  describe "#mark_failure!" do
    let(:cred) { create(:apple_ads_credential) }

    it "stores a truncated, sanitized error message" do
      long = "a" * 500 + " -----BEGIN EC PRIVATE KEY-----leak-----END EC PRIVATE KEY-----"
      cred.mark_failure!(long)
      expect(cred.last_error.length).to be <= 200
      expect(cred.last_error).not_to include("BEGIN EC PRIVATE KEY")
    end

    it "sanitizes Bearer tokens" do
      cred.mark_failure!("Authorization: Bearer abcdef.token.xyz failed")
      expect(cred.last_error).to include("Bearer [REDACTED]")
    end

    it "sanitizes JWTs" do
      jwt_like = "eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJ4In0.signature"
      cred.mark_failure!("JWT #{jwt_like} invalid")
      expect(cred.last_error).to include("[REDACTED_JWT]")
    end
  end

  describe "Organization association" do
    it "is destroyed when the Organization is destroyed" do
      org = create(:organization)
      create(:apple_ads_credential, organization: org)
      expect { org.destroy! }.to change { AppleAdsCredential.count }.by(-1)
    end
  end

  describe "cache purge on update" do
    before do
      @store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(@store)
    end

    let(:cred) { create(:apple_ads_credential) }

    it "purges cached tokens when sensitive fields change" do
      Rails.cache.write("aso/apple_ads/access_token/#{cred.id}", "stale")
      Rails.cache.write("aso/apple_ads/assertion/#{cred.id}", "stale")
      cred.update!(client_id: "NEWID.00000000-0000-0000-0000-000000000001")
      expect(Rails.cache.read("aso/apple_ads/access_token/#{cred.id}")).to be_nil
      expect(Rails.cache.read("aso/apple_ads/assertion/#{cred.id}")).to be_nil
    end

    it "does NOT purge on non-sensitive field changes" do
      Rails.cache.write("aso/apple_ads/access_token/#{cred.id}", "cached")
      cred.mark_success!  # updates last_successful_at only
      expect(Rails.cache.read("aso/apple_ads/access_token/#{cred.id}")).to eq("cached")
    end

    it "purges scaffold keys on a direct credential destroy" do
      org = cred.organization
      app = create(:apple_app, organization: org, app_store_id: "6401234567")
      Rails.cache.write("aso/apple_ads/scaffold/#{cred.id}/#{app.app_store_id}", [ "c_1", "ag_1" ])

      cred.destroy!

      expect(Rails.cache.read("aso/apple_ads/scaffold/#{cred.id}/#{app.app_store_id}")).to be_nil
    end

    it "purges scaffold keys on an org cascade-destroy (snapshot catches apps before they're reaped)" do
      org = create(:organization)
      app = create(:apple_app, organization: org, app_store_id: "6402345678")
      cred = create(:apple_ads_credential, organization: org)
      Rails.cache.write("aso/apple_ads/scaffold/#{cred.id}/#{app.app_store_id}", [ "c_1", "ag_1" ])
      Rails.cache.write("aso/apple_ads/access_token/#{cred.id}", "stale")
      Rails.cache.write("aso/apple_ads/assertion/#{cred.id}", "stale")

      org.destroy!

      expect(Rails.cache.read("aso/apple_ads/scaffold/#{cred.id}/#{app.app_store_id}")).to be_nil
      expect(Rails.cache.read("aso/apple_ads/access_token/#{cred.id}")).to be_nil
      expect(Rails.cache.read("aso/apple_ads/assertion/#{cred.id}")).to be_nil
    end
  end

  describe "#mark_failure! sanitization (JSON-embedded secrets)" do
    it "sanitizes JSON-embedded secret fields" do
      cred = create(:apple_ads_credential)
      cred.mark_failure!('{"client_secret":"shhh","access_token":"abcd","other":"keep"}')
      expect(cred.last_error).not_to include("shhh")
      expect(cred.last_error).not_to include("abcd")
      expect(cred.last_error).to include("keep")
    end
  end

  describe "#mark_failure! clears last_successful_at" do
    it "sets last_successful_at to nil so last_successful? returns false" do
      cred = create(:apple_ads_credential, last_successful_at: 1.hour.ago)
      expect(cred).to be_last_successful
      cred.mark_failure!("401")
      cred.reload
      expect(cred.last_successful_at).to be_nil
      expect(cred).not_to be_last_successful
    end
  end

  describe "Vaulted private_key_pem (mysigner-26)" do
    let(:kms)                 { instance_double(Aws::KMS::Client) }
    let(:plaintext_dek)       { OpenSSL::Random.random_bytes(32) }
    let(:wrapped_dek)         { "wrapped-#{SecureRandom.hex(16)}".b }
    let(:returned_kms_key_id) { "arn:aws:kms:us-east-1:0:key/test" }
    let(:pem) { SpecCredentialFixtures.ec_private_key }

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

    it "populates private_key_pem_envelope on create with a roundtrip-decryptable envelope" do
      cred = create(:apple_ads_credential, private_key_pem: pem)
      cred.reload

      expect(cred.private_key_pem_envelope).to be_present

      envelope = CredentialVault.unpack(cred.private_key_pem_envelope)
      decrypted = CredentialVault.decrypt(envelope, context: {
        org_id:          cred.organization_id.to_s,
        credential_kind: "apple_ads",
        credential_id:   cred.vault_record_id
      })
      expect(decrypted).to eq(pem)
    end

    it "re-encrypts envelope when private_key_pem rotates" do
      cred = create(:apple_ads_credential)
      initial_envelope = cred.private_key_pem_envelope

      new_pem = OpenSSL::PKey::EC.generate("prime256v1").to_pem
      cred.update!(private_key_pem: new_pem)

      expect(cred.private_key_pem_envelope).to be_present
      expect(cred.private_key_pem_envelope).not_to eq(initial_envelope)
    end

    it "does NOT re-encrypt when only non-vault fields change" do
      # Same WHY as the AndroidKeystore version: gratuitous re-encrypts
      # would invalidate any "envelope unchanged since N" invariants and
      # cost KMS calls on every save.
      #
      # NOTE: use `update!` (which runs the save callback chain) rather than
      # `mark_failure!`, which calls `update_columns` and bypasses callbacks
      # entirely — that would make this test trivially true.
      cred = create(:apple_ads_credential)
      before_envelope = cred.reload.private_key_pem_envelope

      cred.update!(last_successful_at: Time.current)
      expect(cred.reload.private_key_pem_envelope).to eq(before_envelope)
    end

    it "binds the envelope to vault_record_id (swap-attack defense)" do
      cred_a = create(:apple_ads_credential)
      cred_b = create(:apple_ads_credential,
        client_id: "SEARCHADS.11111111-1111-1111-1111-111111111111",
        team_id:   "9876543210",
        private_key_pem: OpenSSL::PKey::EC.generate("prime256v1").to_pem)

      cred_a.update_column(:private_key_pem_envelope, cred_b.private_key_pem_envelope)

      envelope = CredentialVault.unpack(cred_a.reload.private_key_pem_envelope)
      expect {
        CredentialVault.decrypt(envelope, context: {
          org_id:          cred_a.organization_id.to_s,
          credential_kind: "apple_ads",
          credential_id:   cred_a.vault_record_id
        })
      }.to raise_error(CredentialVault::DecryptError)
    end
  end
end
