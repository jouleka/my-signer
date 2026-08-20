require "rails_helper"

RSpec.describe AndroidKeystore, type: :model do
  let(:user) { User.create!(email: "keystore@example.com", password: "SecurePass123!", confirmed_at: Time.current) }
  let(:organization) { Organization.create!(name: "Org", owner: user) }
  let(:android_app) { AndroidApp.create!(organization: organization, package_name: "com.example.app", name: "Example") }
  let(:base_attrs) do
    {
      organization: organization,
      android_app: android_app,
      name: "Release Key",
      keystore_file: "binary-data",
      keystore_password: "storepass",
      key_password: "keypass",
      key_alias: "release"
    }
  end

  let(:validator_result) do
    Android::KeystoreValidator::Result.new(
      valid_until: 1.year.from_now,
      valid_from: Time.current,
      alias: "release",
      certificate_subject: "CN=Example",
      certificate_issuer: "CN=Example",
      fingerprints: {}
    )
  end

  before do
    validator_double = instance_double(Android::KeystoreValidator)
    allow(validator_double).to receive(:validate!).and_return(validator_result)
    allow(Android::KeystoreValidator).to receive(:new).and_return(validator_double)
  end

  describe ".expiring_within" do
    it "returns keystores expiring within the provided window" do
      soon = described_class.create!(base_attrs).tap { |k| k.update_column(:expires_at, 5.days.from_now.to_date) }
      later = described_class.create!(base_attrs.merge(name: "Later Key")).tap { |k| k.update_column(:expires_at, 60.days.from_now.to_date) }
      expired = described_class.create!(base_attrs.merge(name: "Expired Key")).tap { |k| k.update_column(:expires_at, 2.days.ago.to_date) }

      results = described_class.expiring_within(30)

      expect(results).to include(soon, expired)
      expect(results).not_to include(later)
    end
  end

  describe "#expired?" do
    it "returns true when expires_at is past" do
      keystore = described_class.create!(base_attrs)
      keystore.update_column(:expires_at, 1.day.ago.to_date)
      expect(keystore).to be_expired
    end
  end

  describe "#expiring_soon?" do
    it "returns true when inside the window" do
      keystore = described_class.create!(base_attrs)
      keystore.update_column(:expires_at, 10.days.from_now.to_date)
      expect(keystore.expiring_soon?(15)).to be(true)
      expect(keystore.expiring_soon?(5)).to be(false)
    end
  end

  describe "#days_until_expiry" do
    it "returns integer day difference" do
      keystore = described_class.create!(base_attrs)
      keystore.update_column(:expires_at, Date.current + 7)
      expect(keystore.days_until_expiry).to eq(7)
    end
  end

  describe "keytool validation callback" do
    it "updates expires_at based on validator result" do
      keystore = described_class.create!(base_attrs)
      expect(Android::KeystoreValidator).to have_received(:new)
      expect(keystore.expires_at).to eq(validator_result.valid_until.to_date)
    end

    it "prevents save when validator raises an error" do
      failing_validator = instance_double(Android::KeystoreValidator)
      allow(failing_validator).to receive(:validate!).and_raise(Android::KeystoreValidator::ValidationError, "bad keystore")
      allow(Android::KeystoreValidator).to receive(:new).and_return(failing_validator)

      keystore = described_class.new(base_attrs)
      expect { keystore.save! }.to raise_error(ActiveRecord::RecordNotSaved)
    end
  end

  describe "Vaulted keystore secrets (mysigner-26)" do
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

    it "populates all three envelope columns on create" do
      # WHY: keystore_file, keystore_password, and key_password each have
      # their own envelope column and their own `kind` in the EncryptionContext.
      # If any of the three didn't fire, signing operations after the
      # read-switch (mysigner-28) would fail on that specific secret.
      ks = described_class.create!(base_attrs)
      ks.reload

      expect(ks.keystore_file_envelope).to     be_present
      expect(ks.keystore_password_envelope).to be_present
      expect(ks.key_password_envelope).to      be_present
    end

    it "round-trips binary keystore_file bytes through pack/unpack" do
      # WHY: keystore_file is a `binary` column (bytea), not text. The
      # pack/unpack path base64-encodes the ciphertext, so binary inputs
      # must survive encoding/decoding without truncation or mangling.
      binary_bytes = ("\x00\xff" * 16).b
      ks = described_class.create!(base_attrs.merge(keystore_file: binary_bytes))

      envelope = CredentialVault.unpack(ks.reload.keystore_file_envelope)
      decrypted = CredentialVault.decrypt(envelope, context: {
        org_id:          ks.organization_id.to_s,
        credential_kind: "android_keystore",
        credential_id:   ks.vault_record_id
      })
      expect(decrypted).to eq(binary_bytes)
      expect(decrypted.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it "uses distinct `kind` per attribute (defends against intra-row swaps)" do
      # WHY: an attacker who copies keystore_password_envelope into the
      # key_password_envelope column would have a password move within the row.
      # The `kind` in the EncryptionContext differs between the two columns
      # ("android_keystore_password" vs "android_key_password"), so decrypt
      # with the wrong kind fails.
      ks = described_class.create!(base_attrs)
      ks.update_column(:key_password_envelope, ks.keystore_password_envelope)

      envelope = CredentialVault.unpack(ks.reload.key_password_envelope)
      expect {
        CredentialVault.decrypt(envelope, context: {
          org_id:          ks.organization_id.to_s,
          credential_kind: "android_key_password",  # the kind for key_password
          credential_id:   ks.vault_record_id
        })
      }.to raise_error(CredentialVault::DecryptError)
    end

    it "skips re-encryption when no envelope-mapped attribute changes" do
      # WHY: KMS calls cost money + latency, but more importantly, a
      # silent re-encryption on every save would change the wrapped DEK on
      # every row touch — invalidating audit trails that rely on
      # "envelope unchanged since N". Assert the envelope bytes are
      # byte-identical pre/post update.
      ks = described_class.create!(base_attrs)
      before_envelopes = ks.reload.attributes.slice(
        "keystore_file_envelope", "keystore_password_envelope", "key_password_envelope"
      )

      ks.update!(name: "renamed")

      after_envelopes = ks.reload.attributes.slice(
        "keystore_file_envelope", "keystore_password_envelope", "key_password_envelope"
      )
      expect(after_envelopes).to eq(before_envelopes)
    end
  end
end
