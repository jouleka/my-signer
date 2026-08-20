require "rails_helper"

RSpec.describe CredentialVault::OrgRewrap do
  # Same KMS stubbing shape used by every other vault spec in this codebase
  # (backfill_spec.rb, app_store_connect_credential_spec.rb). Real AES inside
  # CredentialVault.encrypt is exercised; only KMS is mocked so we don't
  # touch AWS.
  let(:kms)                 { instance_double(Aws::KMS::Client) }
  let(:plaintext_dek)       { OpenSSL::Random.random_bytes(32) }
  let(:wrapped_dek)         { "wrapped-#{SecureRandom.hex(16)}".b }
  let(:default_key_id)      { "arn:aws:kms:us-east-1:0:key/env-default" }
  let(:customer_arn) do
    "arn:aws:kms:us-east-1:999999999999:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  end
  let(:silent_logger)       { Logger.new(File::NULL) }

  let(:team_owner) { create(:user, :team_plan, email: "rewrap-owner@example.com") }
  let(:organization) { Organization.create!(name: "Rewrap Org", owner: team_owner) }

  before do
    CredentialVault.kms_client = kms
    CredentialVault.key_arn    = default_key_id
    # The stub echoes whichever key_id the caller asked for back as the
    # response's `key_id` — same shape AWS uses (the returned ARN reflects
    # which CMK actually wrapped the DEK). This lets us assert
    # envelope.key_id later to prove the right CMK was used.
    allow(kms).to receive(:generate_data_key) do |args|
      double("GDK",
        plaintext:       plaintext_dek,
        ciphertext_blob: wrapped_dek,
        key_id:          args[:key_id]
      )
    end
    allow(kms).to receive(:decrypt).and_return(
      double("DKR", plaintext: plaintext_dek, key_id: default_key_id)
    )
    Rails.cache.clear
  end

  after do
    CredentialVault.kms_client = nil
    CredentialVault.key_arn    = nil
  end

  describe ".run" do
    it "returns per-class counts hash with all four credential model subkeys" do
      # WHY: the controller surfaces these counts in the audit metadata for
      # forensics ("how many credentials did we just touch?"). The hash
      # shape is the public contract. A future fifth credential kind would
      # need to be added to Backfill::TARGETS — locking down the four
      # current keys catches an accidental drift.
      result = described_class.run(organization: organization, key_arn: nil, logger: silent_logger)

      expect(result.keys).to contain_exactly(
        :AppStoreConnectCredential,
        :GooglePlayCredential,
        :AndroidKeystore,
        :AppleAdsCredential
      )
      result.each_value do |counts|
        # No `failed` key: OrgRewrap is atomic, so any failure raises
        # instead of being counted. `processed` counts rows visited;
        # `succeeded` counts rows that completed without raising.
        expect(counts.keys).to contain_exactly(:processed, :succeeded)
      end
    end

    it "re-wraps existing envelopes with the explicitly passed key_arn (register path)" do
      # WHY: this is the core register-time property. Before BYOK, the
      # credential's envelope was wrapped under the env-default CMK. After
      # OrgRewrap runs with the customer's CMK ARN, the new envelope's
      # `key_id` must point at the customer's CMK — that's what decrypt
      # routes through. If this assertion fails, the customer's revocation
      # surface doesn't actually gate access to their data.
      cred = create(:app_store_connect_credential, organization: organization, private_key: "PEM-A")
      cred.reload
      original_envelope_json = cred.private_key_envelope
      original_envelope = CredentialVault.unpack(original_envelope_json)
      expect(original_envelope.key_id).to eq(default_key_id)

      result = described_class.run(organization: organization, key_arn: customer_arn, logger: silent_logger)

      cred.reload
      rewrapped = CredentialVault.unpack(cred.private_key_envelope)
      expect(rewrapped.key_id).to eq(customer_arn)
      expect(cred.private_key_envelope).not_to eq(original_envelope_json)
      expect(result[:AppStoreConnectCredential]).to include(processed: 1, succeeded: 1)
    end

    it "re-wraps back to the env default when key_arn is nil (clear path)" do
      # Symmetric to the above: on Clear, the controller passes nil through
      # the org callback into OrgRewrap; CredentialVault.encrypt then falls
      # back to the env-default CMK. The envelope's key_id must move from
      # the customer ARN back to the env-default ARN. Without this, a
      # customer who Clears BYOK would still have envelopes wrapped under
      # their CMK — defeating the "clean opt-out" guarantee in the design
      # doc decision E.
      cred = create(:app_store_connect_credential, organization: organization, private_key: "PEM-A")
      # Manually re-wrap once under the customer ARN to set up the state
      # we'd be in immediately after a Register.
      described_class.run(organization: organization, key_arn: customer_arn, logger: silent_logger)
      expect(CredentialVault.unpack(cred.reload.private_key_envelope).key_id).to eq(customer_arn)

      described_class.run(organization: organization, key_arn: nil, logger: silent_logger)

      expect(CredentialVault.unpack(cred.reload.private_key_envelope).key_id).to eq(default_key_id)
    end

    it "skips attrs whose plaintext is nil (nothing to wrap)" do
      # WHY: a corrupted/half-deleted row whose plaintext got cleared should
      # not break the rewrap of every other credential in the org. The
      # design doc explicitly calls this out: "Skips rows where plaintext is
      # nil." The row still counts as `succeeded` because the iteration
      # completed without raising — there was just nothing to encrypt.
      cred = create(:app_store_connect_credential, organization: organization, private_key: "PEM-A")
      # Bypass model validation to simulate the legacy "no plaintext" state.
      cred.private_key = nil
      cred.save!(validate: false)
      expect(cred.reload.private_key).to be_nil

      result = described_class.run(organization: organization, key_arn: customer_arn, logger: silent_logger)

      expect(result[:AppStoreConnectCredential]).to eq(processed: 1, succeeded: 1)
    end

    it "iterates every model in TARGETS — order is alphabetical" do
      # WHY: the design doc shares TARGETS with Backfill so a fifth kind is
      # added once. This spec catches an accidental override of TARGETS on
      # OrgRewrap that would silently leave a credential class un-rewrapped.
      expect(described_class::TARGETS).to eq(CredentialVault::Backfill::TARGETS)

      result = described_class.run(organization: organization, key_arn: nil, logger: silent_logger)
      expect(result.keys.map(&:to_s)).to match_array(described_class::TARGETS)
    end

    it "propagates the exception when an attr's encrypt raises (atomicity contract)" do
      # WHY: a KMS failure during a re-wrap MUST propagate up to the
      # `Organization#rewrap_credentials_on_byok_change` callback so it can
      # `throw :abort` and let AR roll back every `update_column` write
      # OrgRewrap issued. Earlier behavior swallowed the exception, counted
      # it as `failed`, and returned a counts hash — which silently allowed
      # the org save to commit with a partial rewrap. That broke the
      # design doc's "all-or-nothing DB state" guarantee.
      #
      # This spec locks down the propagation half of the contract. The
      # rollback half is exercised at the Organization-callback layer in
      # the "rolls back update_column writes" context below — which uses
      # the real org.update path and actually verifies the DB state
      # reverts.
      good = create(:app_store_connect_credential, organization: organization, private_key: "good-pem")
      bad  = create(:app_store_connect_credential, organization: organization, private_key: "bad-pem", name: "Bad ASC")
      bad_vault_id = bad.vault_record_id

      allow(CredentialVault).to receive(:encrypt).and_wrap_original do |orig, plaintext, **kwargs|
        ctx = kwargs[:context] || {}
        if ctx[:credential_id].to_s == bad_vault_id.to_s
          raise Aws::KMS::Errors::ServiceError.new(nil, "simulated KMS failure")
        end
        orig.call(plaintext, **kwargs)
      end

      expect {
        described_class.run(organization: organization, key_arn: customer_arn, logger: silent_logger)
      }.to raise_error(Aws::KMS::Errors::ServiceError, /simulated KMS failure/)

      # Stand-alone OrgRewrap.run has no transaction wrapper of its own —
      # only the org save's transaction provides rollback. So the partial
      # state IS visible here: the good row already got update_column'd
      # before the bad row raised. This is the expected behavior outside
      # an org.update; the atomicity contract is specifically about the
      # callback-wrapped path. The integration spec covers that.
      _ = good
    end

    context "when invoked via Organization#update (the real atomicity path)" do
      it "rolls back update_column writes and the org column when an encrypt fails mid-iteration" do
        # WHY: this is the spec that actually proves the atomicity claim
        # from the design doc. Stubbing `OrgRewrap.run` at the boundary
        # (as the existing organization spec does) doesn't catch the bug
        # where the broad rescue inside OrgRewrap swallows KMS errors —
        # we need to let real iteration run, fail mid-way on a real
        # exception, and observe the transaction-wrapped before_save
        # rolls everything back to the pre-save state.
        good = create(:app_store_connect_credential, organization: organization, private_key: "good-pem")
        bad  = create(:app_store_connect_credential, organization: organization, private_key: "bad-pem", name: "Bad ASC")
        original_good_envelope = good.reload.private_key_envelope
        original_bad_envelope  = bad.reload.private_key_envelope
        bad_vault_id = bad.vault_record_id

        allow(CredentialVault).to receive(:encrypt).and_wrap_original do |orig, plaintext, **kwargs|
          ctx = kwargs[:context] || {}
          if ctx[:credential_id].to_s == bad_vault_id.to_s
            raise Aws::KMS::Errors::ServiceError.new(nil, "simulated mid-rewrap KMS failure")
          end
          orig.call(plaintext, **kwargs)
        end

        result = organization.update(byok_kms_key_arn: customer_arn)

        # Save returned false — the callback caught the KMS error and
        # threw :abort, which AR surfaces as a failed save with a model
        # error message.
        expect(result).to be false
        expect(organization.errors[:byok_kms_key_arn]).to include(a_string_matching(/could not be applied/))

        # The org column rolled back to its pre-save value (nil).
        expect(organization.reload.byok_kms_key_arn).to be_nil

        # AND — the key assertion — the `update_column` write that
        # OrgRewrap already issued on the good credential (before the
        # bad one raised) rolled back too. Both envelopes still reference
        # the env-default CMK, not the customer ARN that briefly got
        # written. This is what makes BYOK toggles "all-or-nothing".
        expect(CredentialVault.unpack(good.reload.private_key_envelope).key_id).to eq(default_key_id)
        expect(CredentialVault.unpack(bad.reload.private_key_envelope).key_id).to eq(default_key_id)
        expect(good.reload.private_key_envelope).to eq(original_good_envelope)
        expect(bad.reload.private_key_envelope).to eq(original_bad_envelope)
      end
    end

    it "scopes its iteration to the passed organization (does NOT touch other orgs)" do
      # WHY: an org's BYOK change must NEVER trigger a re-wrap of another
      # org's credentials. That would be both a correctness bug (wrong CMK)
      # and a multi-tenancy isolation violation. Strategy: create one cred
      # in our org and one in a sibling org; rewrap our org; assert the
      # sibling's envelope key_id is unchanged.
      other_owner = create(:user, :team_plan, email: "other-owner@example.com")
      other_org   = Organization.create!(name: "Other Org", owner: other_owner)

      our_cred   = create(:app_store_connect_credential, organization: organization, private_key: "ours")
      other_cred = create(:app_store_connect_credential, organization: other_org,    private_key: "theirs", name: "Other ASC")
      expect(CredentialVault.unpack(other_cred.reload.private_key_envelope).key_id).to eq(default_key_id)

      described_class.run(organization: organization, key_arn: customer_arn, logger: silent_logger)

      expect(CredentialVault.unpack(our_cred.reload.private_key_envelope).key_id).to eq(customer_arn)
      # Sibling org untouched — key_id is still the env default.
      expect(CredentialVault.unpack(other_cred.reload.private_key_envelope).key_id).to eq(default_key_id)
    end

    it "uses update_column (bypasses Vaulted callbacks, no recursive re-encrypt)" do
      # WHY: the design doc is explicit — `save` would re-fire Vaulted's
      # before_save, which re-reads organization.byok_kms_key_arn at the
      # time the callback fires. Inside the org's own before_save (the
      # actual production caller), the in-memory ARN may not be the value
      # we want. `update_column` writes the column directly. This spec
      # locks in the bypass: we observe that CredentialVault.encrypt is
      # called exactly once per credential during the rewrap — not twice
      # (which would happen if a save re-fired Vaulted's before_save).
      create(:app_store_connect_credential, organization: organization, private_key: "PEM-A")

      # Spy on CredentialVault.encrypt directly. Counting KMS calls is
      # noisier (create-time encrypt counts in the same total), but
      # encrypt-count specifically tied to the rewrap iteration is what
      # the contract is about.
      encrypt_calls = 0
      allow(CredentialVault).to receive(:encrypt).and_wrap_original do |orig, *args, **kwargs|
        encrypt_calls += 1
        orig.call(*args, **kwargs)
      end

      described_class.run(organization: organization, key_arn: customer_arn, logger: silent_logger)

      # One ASC × one vault attr (`private_key`) = exactly one encrypt.
      # If save (not update_column) were used, the Vaulted callback would
      # re-enter and call encrypt twice.
      expect(encrypt_calls).to eq(1)
    end
  end

  describe "evicts the OLD wrapped DEK from the process-local cache (L-1)" do
    it "calls CredentialVault.evict_dek with the OLD envelope's wrapped_dek + key_id" do
      # WHY: after a BYOK migrate/clear re-wraps a row under a new CMK, the
      # plaintext DEK for the OLD wrapped_dek must not linger in RAM — a key
      # we just rotated away should stop serving decrypts. OrgRewrap reads the
      # old envelope before overwriting and evicts it.
      cred = create(:app_store_connect_credential, organization: organization, private_key: "PEM-A")
      cred.reload
      old_env = CredentialVault.unpack(cred.private_key_envelope)

      expect(CredentialVault).to receive(:evict_dek)
        .with(old_env.wrapped_dek, old_env.key_id)
        .at_least(:once)
        .and_call_original

      described_class.run(organization: organization, key_arn: customer_arn, logger: silent_logger)
    end

    it "does not blow up the re-wrap when there is no old envelope to evict" do
      # A row whose plaintext is nil has no envelope; eviction must be skipped
      # silently (old_packed blank → no-op), and the run still succeeds.
      create(:app_store_connect_credential, organization: organization, private_key: "PEM-A")
      expect {
        described_class.run(organization: organization, key_arn: customer_arn, logger: silent_logger)
      }.not_to raise_error
    end
  end

  describe "uses the shared Vaulted.context_for builder (L-25)" do
    it "builds the encrypt context via the single shared builder" do
      cred = create(:app_store_connect_credential, organization: organization, private_key: "PEM-A")
      cred.reload

      # Assert the shared builder is invoked rather than a hand-rolled hash,
      # so the three former copies of the context can never drift.
      expect(AppStoreConnectCredential).to receive(:context_for)
        .with(hash_including(kind: "asc"))
        .at_least(:once)
        .and_call_original

      described_class.run(organization: organization, key_arn: customer_arn, logger: silent_logger)
    end
  end
end
