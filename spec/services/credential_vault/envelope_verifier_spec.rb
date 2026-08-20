require "rails_helper"

RSpec.describe CredentialVault::EnvelopeVerifier do
  # Same KMS stubbing shape used by every other vault spec
  # (backfill_spec.rb, org_rewrap_spec.rb). Real AES inside
  # CredentialVault.encrypt/.decrypt is exercised end-to-end; only KMS is
  # mocked so we don't touch AWS.
  let(:kms)                 { instance_double(Aws::KMS::Client) }
  let(:plaintext_dek)       { OpenSSL::Random.random_bytes(32) }
  let(:wrapped_dek)         { "wrapped-#{SecureRandom.hex(16)}".b }
  let(:returned_kms_key_id) { "arn:aws:kms:us-east-1:0:key/test" }
  let(:silent_logger)       { Logger.new(File::NULL) }

  # Realistic-enough service account JSON to pass GooglePlayCredential's
  # `validate_service_account_json_structure` validator. The verifier doesn't
  # care about the content — only that the row can be saved through the
  # Vaulted callback so an envelope gets written.
  let(:google_play_json) do
    {
      type:          "service_account",
      project_id:    "test-project",
      private_key:   "-----BEGIN PRIVATE KEY-----\nfake\n-----END PRIVATE KEY-----",
      client_email:  "test@test-project.iam.gserviceaccount.com",
      client_id:     "1234567890"
    }.to_json
  end

  before do
    CredentialVault.kms_client = kms
    CredentialVault.key_arn    = returned_kms_key_id
    allow(kms).to receive(:generate_data_key) do |args|
      double("GDK",
        plaintext:       plaintext_dek,
        ciphertext_blob: wrapped_dek,
        key_id:          args[:key_id] || returned_kms_key_id
      )
    end
    allow(kms).to receive(:decrypt).and_return(
      double("DKR", plaintext: plaintext_dek, key_id: returned_kms_key_id)
    )

    # Stub keytool: AndroidKeystore#validate_credentials_with_keytool!
    # shells out to a real `keytool` binary against a real .jks file at
    # save time. Mirrors the stub pattern from spec/models/android_keystore_spec.rb.
    # The verifier itself never calls into the validator — it only reads
    # envelopes — but the factory's `create!` triggers the before_save
    # callback that does.
    validator_result = Android::KeystoreValidator::Result.new(
      valid_until:         1.year.from_now,
      valid_from:          Time.current,
      alias:               "release",
      certificate_subject: "CN=Example",
      certificate_issuer:  "CN=Example",
      fingerprints:        {}
    )
    validator_double = instance_double(Android::KeystoreValidator, validate!: validator_result)
    allow(Android::KeystoreValidator).to receive(:new).and_return(validator_double)

    Rails.cache.clear
  end

  after do
    CredentialVault.kms_client = nil
    CredentialVault.key_arn    = nil
  end

  describe ".run" do
    it "returns a hash keyed by every credential model class in TARGETS" do
      # WHY: the verifier replaces a 30-day soak period before the read-path
      # flip. The report's purpose is to prove EVERY model class was visited
      # — a silent skip of one class would let unverified envelopes slip
      # into the flip. Locking down the key set catches accidental drift
      # of TARGETS away from Backfill's source of truth.
      result = described_class.run(logger: silent_logger)

      expect(result.keys).to contain_exactly(
        :AppStoreConnectCredential,
        :GooglePlayCredential,
        :AndroidKeystore,
        :AppleAdsCredential
      )
      result.each_value do |counts|
        expect(counts.keys).to contain_exactly(
          :checked, :ok, :missing_envelope, :decrypt_failed, :failures
        )
      end
      # Shares its TARGETS list with Backfill — a fifth credential kind
      # needs to be added in exactly one place.
      expect(described_class::TARGETS).to eq(CredentialVault::Backfill::TARGETS)
    end

    it "counts rows whose envelope decrypts cleanly as ok, with zero failures" do
      # WHY: this is the happy path that gates the read-path flip. Every
      # row with an envelope must round-trip through unpack + decrypt. If
      # the verifier's own decrypt loop is broken, every envelope in
      # production would be (incorrectly) flagged as failed — so the happy
      # path must explicitly prove ok > 0 and failed == 0.
      create(:app_store_connect_credential, private_key: "PEM-A")
      create(:google_play_credential, service_account_json: google_play_json)
      create(:android_keystore, keystore_file: "jks-bytes", keystore_password: "pw1", key_password: "pw2")

      result = described_class.run(logger: silent_logger)

      expect(result[:AppStoreConnectCredential][:ok]).to be >= 1
      expect(result[:GooglePlayCredential][:ok]).to       be >= 1
      # AndroidKeystore has three vault_attrs registered — one row → three
      # (row, attr) pairs all ok.
      expect(result[:AndroidKeystore][:ok]).to            be >= 3

      result.each_value do |counts|
        expect(counts[:decrypt_failed]).to eq(0)
        expect(counts[:failures]).to       be_empty
      end
    end

    it "counts rows with a NULL envelope as missing_envelope (not as failed)" do
      # WHY: Backfill explicitly skips rows whose plaintext is nil. A NULL
      # envelope on such a row is the expected steady state, not a bug —
      # there was nothing to wrap. If the verifier counted these as failed,
      # every legitimate "nothing to wrap" row in production would block
      # the read-path flip. This is the spec that protects against that
      # over-eager classification.
      cred = create(:app_store_connect_credential, private_key: "PEM-A")
      cred.update_columns(private_key_envelope: nil)
      expect(cred.reload.private_key_envelope).to be_nil

      result = described_class.run(logger: silent_logger)

      asc = result[:AppStoreConnectCredential]
      expect(asc[:missing_envelope]).to be >= 1
      expect(asc[:decrypt_failed]).to   eq(0)
      expect(asc[:failures]).to         be_empty
    end

    it "records a decrypt failure with full per-row context and continues iterating" do
      # WHY: the operator needs every broken row in ONE pass, not the first
      # one then a re-run, then the next, etc. Iteration MUST continue past
      # a failure (mirrors Backfill's per-row rescue, NOT OrgRewrap's
      # propagate-and-abort). And the failure record must carry enough
      # context to locate the row in the DB (`class`, `record_id`,
      # `organization_id`) and the affected attr (`attr_name`) plus the
      # error itself (`error_class`, `error_message`) — without it the
      # operator can't triage.
      cred_bad  = create(:app_store_connect_credential, private_key: "bad",  name: "Bad ASC")
      cred_good = create(:app_store_connect_credential, private_key: "good", name: "Good ASC")
      bad_vault_id = cred_bad.vault_record_id

      # Real decrypt would call KMS. Selectively raise on cred_bad's
      # context only, by inspecting credential_id in the context hash.
      # Stringify keys defensively — production code uses symbols, but
      # this stub guards against either shape.
      allow(CredentialVault).to receive(:decrypt).and_wrap_original do |orig, envelope, **kwargs|
        ctx = (kwargs[:context] || {}).transform_keys(&:to_sym)
        if ctx[:credential_id].to_s == bad_vault_id.to_s
          raise CredentialVault::DecryptError, "simulated decrypt failure for cred_bad"
        end
        orig.call(envelope, **kwargs)
      end

      result = described_class.run(logger: silent_logger)

      asc = result[:AppStoreConnectCredential]
      expect(asc[:decrypt_failed]).to eq(1)
      expect(asc[:ok]).to             be >= 1  # cred_good still verified

      expect(asc[:failures].size).to eq(1)
      failure = asc[:failures].first
      expect(failure).to include(
        class:           "AppStoreConnectCredential",
        record_id:       cred_bad.id,
        organization_id: cred_bad.organization_id,
        attr_name:       :private_key,
        error_class:     "CredentialVault::DecryptError"
      )
      expect(failure[:error_message]).to match(/simulated decrypt failure for cred_bad/)

      # Sanity: cred_good's verification was not skipped by the early failure.
      expect(cred_good.reload.private_key_envelope).to be_present
    end

    it "treats CustomerKeyRevoked the same as any other decrypt failure (recorded, not raised)" do
      # WHY: CustomerKeyRevoked is the BYOK-revocation signal — it inherits
      # from DecryptError but is a distinct class that callers may match on.
      # The verifier must catch it like any other decrypt error so an org
      # whose customer CMK is revoked shows up in the report instead of
      # aborting the whole verification mid-iteration. (If a real BYOK
      # customer has revoked their CMK on the day we run pre-flight, the
      # operator needs to know that AND continue checking every other org.)
      create(:app_store_connect_credential, private_key: "PEM-A")
      allow(CredentialVault).to receive(:decrypt).and_raise(
        CredentialVault::CustomerKeyRevoked, "customer CMK access denied: simulated"
      )

      result = described_class.run(logger: silent_logger)

      asc = result[:AppStoreConnectCredential]
      expect(asc[:decrypt_failed]).to be >= 1
      expect(asc[:failures].first[:error_class]).to eq("CredentialVault::CustomerKeyRevoked")
    end

    it "maintains the invariant checked == ok + missing_envelope + decrypt_failed" do
      # WHY: a counts hash that doesn't sum to `checked` is unreliable as a
      # verification report — the operator can't trust "ok=N" if N+missing+
      # failed != checked. The invariant is also the simplest test that
      # exercises a MIX of all three classifications in the same model
      # class, end-to-end. Build one of each.
      create(:app_store_connect_credential, private_key: "good-1", name: "G1") # → ok
      create(:app_store_connect_credential, private_key: "good-2", name: "G2") # → ok
      missing = create(:app_store_connect_credential, private_key: "M", name: "M")
      missing.update_columns(private_key_envelope: nil)                         # → missing
      bad = create(:app_store_connect_credential, private_key: "B", name: "B")
      bad_vault_id = bad.vault_record_id                                        # → fail

      allow(CredentialVault).to receive(:decrypt).and_wrap_original do |orig, envelope, **kwargs|
        ctx = (kwargs[:context] || {}).transform_keys(&:to_sym)
        if ctx[:credential_id].to_s == bad_vault_id.to_s
          raise CredentialVault::DecryptError, "simulated"
        end
        orig.call(envelope, **kwargs)
      end

      result = described_class.run(logger: silent_logger)

      # Aggregate across every class. The invariant must hold per-class AND
      # across the whole sweep, so do both.
      result.each_value do |c|
        expect(c[:checked]).to eq(c[:ok] + c[:missing_envelope] + c[:decrypt_failed]),
          "per-class invariant broken: #{c.inspect}"
      end

      asc = result[:AppStoreConnectCredential]
      # At least one of each, all summing.
      expect(asc[:ok]).to               be >= 2
      expect(asc[:missing_envelope]).to be >= 1
      expect(asc[:decrypt_failed]).to   eq(1)
      expect(asc[:checked]).to eq(asc[:ok] + asc[:missing_envelope] + asc[:decrypt_failed])
    end

    it "records failures separately per (row, attr) pair on multi-attr models like AndroidKeystore" do
      # WHY: AndroidKeystore has three vault_attrs (keystore_file,
      # keystore_password, key_password). If one of them decrypt-fails on
      # a row, only that pair should be flagged — the other two stay ok.
      # Counting at the (row, attr) granularity matters for triage: the
      # operator needs to know WHICH attr broke, not just "the row is bad".
      ks = create(:android_keystore,
                  keystore_file:     "jks-bytes",
                  keystore_password: "kpw",
                  key_password:      "kp")
      ks_vault_id = ks.vault_record_id

      # Fail decrypt only when the context's credential_kind is the
      # password-attr kind. The other two attrs on the same row should
      # decrypt cleanly.
      allow(CredentialVault).to receive(:decrypt).and_wrap_original do |orig, envelope, **kwargs|
        ctx = (kwargs[:context] || {}).transform_keys(&:to_sym)
        if ctx[:credential_id].to_s == ks_vault_id.to_s &&
           ctx[:credential_kind].to_s == "android_keystore_password"
          raise CredentialVault::DecryptError, "simulated bad password envelope"
        end
        orig.call(envelope, **kwargs)
      end

      result = described_class.run(logger: silent_logger)

      aks = result[:AndroidKeystore]
      expect(aks[:checked]).to        be >= 3   # one row × three attrs
      expect(aks[:ok]).to             be >= 2   # keystore_file + key_password
      expect(aks[:decrypt_failed]).to eq(1)     # keystore_password only
      expect(aks[:failures].size).to  eq(1)
      expect(aks[:failures].first).to include(
        class:     "AndroidKeystore",
        record_id: ks.id,
        attr_name: :keystore_password
      )
    end
  end

  describe "uses the shared Vaulted.context_for builder (L-25)" do
    it "verifies via the single shared context builder, not a hand-rolled hash" do
      # WHY: the verifier must use the EXACT same context the writer used, or
      # every row would falsely fail decrypt. Routing through the shared
      # builder is what guarantees byte-identical context across the three
      # former copies (Vaulted, OrgRewrap, EnvelopeVerifier).
      create(:app_store_connect_credential, private_key: "PEM-A")

      expect(AppStoreConnectCredential).to receive(:context_for)
        .with(hash_including(kind: "asc"))
        .at_least(:once)
        .and_call_original

      result = described_class.run(logger: silent_logger)
      expect(result[:AppStoreConnectCredential][:ok]).to be >= 1
      expect(result[:AppStoreConnectCredential][:decrypt_failed]).to eq(0)
    end
  end
end
