require "rails_helper"

RSpec.describe AppStoreConnectCredential, type: :model do
  describe "#mark_sync_failure! sanitization" do
    let(:cred) { create(:app_store_connect_credential) }
    it "redacts PEM before persisting" do
      cred.mark_sync_failure!("-----BEGIN EC PRIVATE KEY-----\nX\n-----END EC PRIVATE KEY-----")
      expect(cred.reload.last_sync_error).to include("[REDACTED_PEM]")
    end
  end

  describe "JWT cache invalidation" do
    before do
      @store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(@store)
    end

    let(:cred) { create(:app_store_connect_credential) }
    before { Rails.cache.write("asc_jwt:#{cred.id}", "cached-jwt", expires_in: 13.minutes) }

    it "purges cached JWT on private_key update" do
      new_key = OpenSSL::PKey::EC.generate("prime256v1").to_pem
      cred.update!(private_key: new_key)
      expect(Rails.cache.read("asc_jwt:#{cred.id}")).to be_nil
    end

    it "purges cached JWT on destroy" do
      id = cred.id
      cred.destroy!
      expect(Rails.cache.read("asc_jwt:#{id}")).to be_nil
    end

    it "does NOT purge on unrelated field update" do
      cred.update!(name: "renamed")
      expect(Rails.cache.read("asc_jwt:#{cred.id}")).to eq("cached-jwt")
    end

    it "purges cached JWT on key_id rotation" do
      cred.update!(key_id: "A#{SecureRandom.hex(6).upcase}BCDE")
      expect(Rails.cache.read("asc_jwt:#{cred.id}")).to be_nil
    end

    it "purges cached JWT on issuer_id rotation" do
      cred.update!(issuer_id: SecureRandom.uuid)
      expect(Rails.cache.read("asc_jwt:#{cred.id}")).to be_nil
    end
  end

  describe "Vaulted private_key (mysigner-26)" do
    # All tests in this block need an explicitly configured CredentialVault.
    # Without configuration, the Vaulted concern no-ops (verified separately
    # below), which lets existing tests keep passing unchanged.
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

    it "assigns vault_record_id in Ruby before INSERT" do
      # WHY: the UUID needs to exist in Ruby (not just the DB default) so that
      # CredentialVault.encrypt can use it in the EncryptionContext at write
      # time. If the DB default fired instead, the in-memory record would
      # encrypt with one UUID and the DB row would have another — breaking
      # decrypt on the very next read.
      cred = build(:app_store_connect_credential)
      expect(cred.vault_record_id).to be_nil

      cred.save!
      expect(cred.vault_record_id).to match(
        /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
      )
    end

    it "populates private_key_envelope on create with a roundtrip-decryptable envelope" do
      cred = create(:app_store_connect_credential, private_key: "PEM-A")
      cred.reload

      expect(cred.private_key_envelope).to be_present

      # The packed envelope decrypts back to the plaintext we wrote, using the
      # same context the concern built. This is the core "did dual-write
      # actually work" assertion.
      envelope = CredentialVault.unpack(cred.private_key_envelope)
      decrypted = CredentialVault.decrypt(envelope, context: {
        org_id:          cred.organization_id.to_s,
        credential_kind: "asc",
        credential_id:   cred.vault_record_id
      })
      expect(decrypted).to eq("PEM-A")
    end

    it "re-encrypts envelope when private_key changes" do
      cred = create(:app_store_connect_credential, private_key: "PEM-A")
      initial_envelope = cred.private_key_envelope

      cred.update!(private_key: "PEM-B")
      expect(cred.private_key_envelope).to be_present
      expect(cred.private_key_envelope).not_to eq(initial_envelope)
    end

    it "skips KMS round-trip when private_key did NOT change" do
      # WHY: KMS calls cost money + latency. Saves that update unrelated
      # fields (last_synced_at, name, etc.) shouldn't trigger a re-encrypt.
      # This guard is what makes the dual-write affordable in production.
      cred = create(:app_store_connect_credential, private_key: "PEM-A")
      expect(kms).to have_received(:generate_data_key).once

      cred.update!(name: "renamed")
      expect(kms).to have_received(:generate_data_key).once
    end

    it "clears the envelope when private_key is set to nil" do
      # The credential model normally validates presence of private_key,
      # so we bypass validation here to exercise the nil-envelope branch
      # in isolation. mysigner-28's backfill respects the same invariant
      # via a CHECK constraint we'll add then.
      cred = create(:app_store_connect_credential, private_key: "PEM-A")
      expect(cred.private_key_envelope).to be_present

      cred.private_key = nil
      cred.save!(validate: false)

      expect(cred.reload.private_key_envelope).to be_nil
    end

    it "binds the envelope to vault_record_id (swap-attack defense)" do
      # WHY: an attacker with DB write access tries to move row B's envelope
      # onto row A. Decrypt with A's context must fail because the AES-GCM
      # auth_tag (and KMS EncryptionContext) were both bound to B's
      # vault_record_id at encrypt time.
      cred_a = create(:app_store_connect_credential, private_key: "PEM-A")
      cred_b = create(:app_store_connect_credential, private_key: "PEM-B")

      # Simulate the swap.
      cred_a.update_column(:private_key_envelope, cred_b.private_key_envelope)

      envelope = CredentialVault.unpack(cred_a.reload.private_key_envelope)
      expect {
        CredentialVault.decrypt(envelope, context: {
          org_id:          cred_a.organization_id.to_s,
          credential_kind: "asc",
          credential_id:   cred_a.vault_record_id
        })
      }.to raise_error(CredentialVault::DecryptError)
    end

    describe "BYOK threading (mysigner-21 sub-ticket 2.3)" do
      # WHY: Vaulted resolves the org's byok_kms_key_arn at every encrypt and
      # threads it into CredentialVault.encrypt as the `key_arn:` kwarg. If
      # that thread breaks, BYOK customers' new credentials would silently
      # encrypt under MySigner's env-default CMK instead of theirs —
      # collapsing the sovereignty property the customer paid for.
      let(:customer_arn) do
        "arn:aws:kms:us-east-1:999999999999:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
      end

      it "passes the org's byok_kms_key_arn into CredentialVault.encrypt when set" do
        # Pre-create the org WITHOUT BYOK so OrgRewrap's before_save doesn't
        # rewrap on the arn-set step (we're testing the Vaulted thread here,
        # not the rewrap). Then attach the ARN via update_column to bypass
        # the callback, and finally CREATE a fresh credential whose
        # save-time encrypt should pick up the now-set ARN.
        org = Organization.create!(name: "BYOK Vault Test", owner: create(:user, :team_plan))
        org.update_column(:byok_kms_key_arn, customer_arn)

        expect(CredentialVault).to receive(:encrypt).with(
          anything,
          context: hash_including(org_id: org.id.to_s, credential_kind: "asc"),
          key_arn: customer_arn
        ).and_call_original

        AppStoreConnectCredential.create!(
          organization: org,
          name: "ASC under BYOK",
          key_id: "KEYID000",
          issuer_id: "ISSUER12345678901234",
          private_key: "PEM-BYOK",
          active: true
        )
      end

      it "passes key_arn: nil when the org has no byok_kms_key_arn set (env default)" do
        # Inverse property: a non-BYOK org's saves must keep passing nil so
        # CredentialVault.encrypt falls through to the env-default CMK.
        org = Organization.create!(name: "Non-BYOK Vault Test", owner: create(:user))
        expect(org.byok_kms_key_arn).to be_nil

        expect(CredentialVault).to receive(:encrypt).with(
          anything,
          context: hash_including(org_id: org.id.to_s),
          key_arn: nil
        ).and_call_original

        AppStoreConnectCredential.create!(
          organization: org,
          name: "ASC default",
          key_id: "KEYID001",
          issuer_id: "ISSUER12345678901234",
          private_key: "PEM-default",
          active: true
        )
      end

      it "collapses a blank ARN to nil (presence guard)" do
        # Defensive — Organization validates with allow_blank, so "" should
        # never actually land in the column, but if it did via a callback-
        # bypass write, Vaulted MUST still pass nil downstream rather than
        # "" (which CredentialVault would try to use as a literal key_id and
        # AWS would reject mid-call).
        org = Organization.create!(name: "Blank ARN Vault Test", owner: create(:user))
        org.update_column(:byok_kms_key_arn, "")

        expect(CredentialVault).to receive(:encrypt).with(
          anything,
          context: hash_including(org_id: org.id.to_s),
          key_arn: nil
        ).and_call_original

        AppStoreConnectCredential.create!(
          organization: org,
          name: "ASC blank arn",
          key_id: "KEYID002",
          issuer_id: "ISSUER12345678901234",
          private_key: "PEM-blank",
          active: true
        )
      end
    end
  end

  describe "Vaulted with KMS not configured" do
    # WHY: in test/dev environments without KMS env vars set, the concern
    # must no-op so existing tests keep passing unchanged. This documents and
    # locks in that contract.
    before do
      CredentialVault.kms_client = nil
      CredentialVault.key_arn    = nil
      # Re-stub ENV lookup to ensure no leakage from CI env vars.
      orig_env = ENV.delete("MYSIGNER_KMS_KEY_ARN")
      @restore_env = -> { ENV["MYSIGNER_KMS_KEY_ARN"] = orig_env if orig_env }
    end

    after { @restore_env&.call }

    it "creates a credential without writing private_key_envelope" do
      expect(CredentialVault).not_to receive(:encrypt)
      cred = create(:app_store_connect_credential, private_key: "PEM-A")
      expect(cred.reload.private_key_envelope).to be_nil
    end

    it "still assigns vault_record_id (UUID assignment is decoupled from KMS)" do
      # Even without KMS, the vault_record_id callback runs because the
      # column is NOT NULL on the DB. (DB default would also kick in.)
      cred = create(:app_store_connect_credential)
      expect(cred.vault_record_id).to be_present
    end
  end
end
