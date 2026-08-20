require "rails_helper"

# Tests the Vaulted concern's public contract directly, independent of any
# specific credential model. AppStoreConnectCredential is the host model here
# only because it's the simplest single-attr `vaults` declaration in the
# codebase. The properties under test apply to every Vaulted model.
#
# These specs pin the mysigner-32 cutover invariants:
#   1. Reads come from `<attr>_envelope`, NOT the AR column.
#   2. The AR column is never written.
#   3. The in-memory cache survives within an object's lifetime, but reload
#      invalidates it and forces a fresh envelope decrypt.
RSpec.describe Vaulted, type: :model do
  let(:user)         { create(:user, :team_plan) }
  let(:organization) { Organization.create!(name: "Vaulted Test Org", owner: user) }

  # Build (not create) so we can control whether/when save runs. The factory
  # asserts presence-validation passes by going through our setter.
  def build_credential(plaintext: "PEM-A")
    build(:app_store_connect_credential, organization: organization, private_key: plaintext)
  end

  describe "read path" do
    it "returns envelope-decrypted plaintext" do
      # WHY: the central post-cutover invariant — the accessor decrypts from
      # `<attr>_envelope` and the value round-trips through reload cleanly.
      #
      # Pre-mysigner-33 this spec also "poisoned" the legacy AR column to
      # prove the accessor didn't fall back to it. With mysigner-33 having
      # dropped that column entirely, the no-AR-fallback property is
      # structural — there's no column to fall back to. The original poison
      # check is therefore impossible AND unnecessary; the surviving
      # assertion still pins the round-trip contract.
      cred = create(:app_store_connect_credential, organization: organization, private_key: "ENVELOPE-PLAINTEXT")
      cred.reload

      expect(cred.private_key).to eq("ENVELOPE-PLAINTEXT")
    end

    it "returns nil when the envelope column is nil" do
      # WHY: a row whose envelope_column is NULL (legacy backfill miss, or a
      # post-Clear-BYOK partial state) must return nil instead of raising.
      # The decision rationale: a missing envelope is operationally
      # indistinguishable from a missing secret; downstream callers already
      # handle nil with `validates :private_key, presence: true` so they'll
      # surface the issue. Raising here would crash the read path on rows
      # the operator could otherwise see in the admin UI.
      cred = create(:app_store_connect_credential, organization: organization, private_key: "PEM-A")
      cred.update_columns(private_key_envelope: nil)
      cred.reload

      expect(cred.private_key).to be_nil
    end

    it "returns blank when envelope column is an empty string" do
      # WHY: belt-and-suspenders for an edge case where a manual SQL fix or
      # buggy migration left an empty string instead of NULL. The accessor
      # treats blank-or-nil identically.
      cred = create(:app_store_connect_credential, organization: organization, private_key: "PEM-A")
      cred.update_columns(private_key_envelope: "")
      cred.reload

      expect(cred.private_key).to be_nil
    end
  end

  describe "write path" do
    it "encrypts to the envelope column on save and never touches the AR column" do
      # WHY: the dual-write phase is over. A save must update only the
      # envelope, leaving the AR column completely untouched — proving that
      # mysigner-33 (which will drop the AR column) is safe to ship.
      cred = build_credential(plaintext: "PEM-INITIAL")
      cred.save!

      # The AR column was never written to by our setter or before_save.
      # write_attribute would be the only place to touch it from inside the
      # concern; assert that the raw column value is whatever AR's default
      # is for an unset text column (nil here, since the schema has no
      # default).
      expect(cred.read_attribute(:private_key)).to be_nil

      # Envelope, on the other hand, is populated and decryptable.
      expect(cred.private_key_envelope).to be_present
      expect(cred.private_key).to eq("PEM-INITIAL")
    end

    it "re-encrypts the envelope when the value is changed" do
      cred = create(:app_store_connect_credential, organization: organization, private_key: "PEM-A")
      initial_envelope = cred.private_key_envelope

      cred.update!(private_key: "PEM-B")
      expect(cred.private_key_envelope).not_to eq(initial_envelope)
      expect(cred.private_key).to eq("PEM-B")
      # AR column still untouched — the rollback window stays clean.
      expect(cred.read_attribute(:private_key)).to be_nil
    end

    it "clears the envelope when the value is set to nil" do
      cred = create(:app_store_connect_credential, organization: organization, private_key: "PEM-A")
      expect(cred.private_key_envelope).to be_present

      cred.private_key = nil
      cred.save!(validate: false)

      expect(cred.reload.private_key_envelope).to be_nil
      expect(cred.private_key).to be_nil
    end
  end

  describe "in-memory cache" do
    it "returns the just-set value from memory without going to the envelope" do
      # WHY: a save-validation cycle reads private_key BEFORE the envelope
      # has been written. The setter must populate an in-memory cache so the
      # getter can return the value the user just typed in (otherwise
      # presence validation on a new record would fail).
      cred = build_credential(plaintext: "PEM-FRESH")

      # Spy on the underlying decrypt — it must NOT fire because the value
      # is served from memory.
      expect(CredentialVault).not_to receive(:decrypt)

      expect(cred.private_key).to eq("PEM-FRESH")
    end

    it "invalidates the cache on reload and re-decrypts from the envelope" do
      # WHY: a reload simulates "fresh from the DB" — any in-memory plaintext
      # must be discarded so a subsequent read pulls the up-to-date envelope.
      # If reload didn't invalidate, a row whose envelope was rotated by
      # OrgRewrap or BYOK toggle would silently keep the old plaintext until
      # the process recycled.
      cred = create(:app_store_connect_credential, organization: organization, private_key: "PEM-A")

      # Confirm the in-memory cache is populated (no decrypt needed).
      expect(CredentialVault).not_to receive(:decrypt)
      expect(cred.private_key).to eq("PEM-A")

      # Now reload and expect a fresh decrypt to fire.
      cred.reload
      RSpec::Mocks.space.proxy_for(CredentialVault).reset
      expect(CredentialVault).to receive(:decrypt).and_call_original

      expect(cred.private_key).to eq("PEM-A")
    end

    it "does not mark the attribute dirty when set to its current value" do
      # WHY: callbacks gated on `saved_change_to_<attr>?` (e.g. JWT cache
      # purges) must not fire on no-op assignments. The classic case:
      # `before_validation :squish_fields` reads-strips-writes back the same
      # plaintext. Without this guard every `update!(name: "x")` would
      # purge the cache. Locks in AR's "no-op write doesn't dirty" semantics
      # for our setter.
      cred = create(:app_store_connect_credential, organization: organization, private_key: "PEM-STABLE")

      # Re-assigning identical value should be a no-op.
      cred.private_key = "PEM-STABLE"
      expect(cred.private_key_changed?).to be(false)

      # Different value should dirty.
      cred.private_key = "PEM-ROTATED"
      expect(cred.private_key_changed?).to be(true)
    end
  end

  describe "dirty-tracking shims" do
    it "exposes `saved_change_to_<attr>?` after a save that changed the value" do
      # WHY: AppStoreConnectCredential and Apple/GooglePlay credentials all
      # depend on this predicate for cache invalidation (e.g.
      # `after_update_commit :purge_cached_jwt_on_update, if:
      # :jwt_signing_material_changed?` which calls
      # `saved_change_to_private_key?`). After cutover, the AR-backed
      # `saved_change_to_*?` predicate is always false because the AR column
      # isn't written. The Vaulted shim restores the semantics by tracking
      # plaintext-level changes.
      cred = create(:app_store_connect_credential, organization: organization, private_key: "PEM-A")

      cred.update!(private_key: "PEM-B")
      expect(cred.saved_change_to_private_key?).to be(true)
    end

    it "returns false from `saved_change_to_<attr>?` after a save that touched only unrelated columns" do
      cred = create(:app_store_connect_credential, organization: organization, private_key: "PEM-A")

      cred.update!(name: "Renamed ASC")
      expect(cred.saved_change_to_private_key?).to be(false)
    end
  end

  describe ".context_for / #vault_context (L-25 shared builder, L-20 blank-id guard)" do
    let(:cred) { create(:app_store_connect_credential, organization: organization, private_key: "PEM-A") }

    it "builds the {org_id, credential_kind, credential_id} context (contents unchanged)" do
      cred.reload
      ctx = AppStoreConnectCredential.context_for(record: cred, kind: "asc")

      expect(ctx).to eq(
        org_id:          organization.id.to_s,
        credential_kind: "asc",
        credential_id:   cred.vault_record_id.to_s
      )
    end

    it "routes the instance #vault_context through the shared class builder (no drift)" do
      cred.reload
      expect(AppStoreConnectCredential).to receive(:context_for)
        .with(record: cred, kind: "asc")
        .and_call_original

      cred.send(:vault_context, "asc")
    end

    it "fails closed with VaultContextError when vault_record_id is blank (L-20)" do
      # A NULL/blank per-record id would weaken the swap-attack binding, so the
      # builder must refuse rather than emit a context with a blank credential_id.
      blank_id_record = build(
        :app_store_connect_credential,
        organization: organization,
        private_key:  "PEM-A"
      )
      allow(blank_id_record).to receive(:vault_record_id).and_return(nil)

      expect {
        AppStoreConnectCredential.context_for(record: blank_id_record, kind: "asc")
      }.to raise_error(Vaulted::VaultContextError, /vault_record_id is blank/)
    end

    it "also fails closed on an empty-string vault_record_id" do
      record = build(:app_store_connect_credential, organization: organization, private_key: "PEM-A")
      allow(record).to receive(:vault_record_id).and_return("")

      expect {
        AppStoreConnectCredential.context_for(record: record, kind: "asc")
      }.to raise_error(Vaulted::VaultContextError)
    end
  end
end
