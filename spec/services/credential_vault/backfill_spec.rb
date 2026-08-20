require "rails_helper"

RSpec.describe CredentialVault::Backfill do
  # mysigner-32 cutover note:
  #
  # Backfill was the one-time mysigner-28 migration tool: convert rows whose
  # envelope was still NULL (pre-Vaulted dual-write) by reading the legacy
  # Rails-AR-encrypted column and writing it into the envelope. Post-cutover,
  # the Vaulted concern no longer reads from the AR column at all, so the
  # "recover plaintext from AR ciphertext" path is gone. The class itself is
  # retained because OrgRewrap shares its TARGETS list; the rake task is
  # documented as obsolete.
  #
  # The tests below cover what still has meaning:
  #   - The precondition guard (raises if KMS isn't configured).
  #   - Idempotency on already-vaulted rows (the where-clause filter).
  #   - The per-class counts hash shape.
  let(:silent_logger) { Logger.new(File::NULL) }

  describe ".run" do
    it "skips rows that already have envelopes populated" do
      # WHY: backfill must be idempotent. The where(envelope IS NULL) clause
      # filters out vaulted rows; this spec pins that filter so a future
      # refactor that broadens it (e.g. iterating EVERY row) doesn't quietly
      # re-encrypt every credential and invalidate any "envelope unchanged
      # since N" invariants.
      cred = create(:app_store_connect_credential, private_key: "PEM-A")
      original_envelope = cred.private_key_envelope
      expect(original_envelope).to be_present

      described_class.run(batch_size: 10, sleep_seconds: 0, logger: silent_logger)

      expect(cred.reload.private_key_envelope).to eq(original_envelope)
    end

    it "returns the per-class counts hash with every credential model present" do
      # WHY: the counts hash is the public contract surfaced in operator logs.
      # All four credential model keys must appear regardless of whether any
      # rows were processed.
      result = described_class.run(batch_size: 10, sleep_seconds: 0, logger: silent_logger)

      expect(result.keys).to contain_exactly(
        :AndroidKeystore,
        :AppleAdsCredential,
        :AppStoreConnectCredential,
        :GooglePlayCredential
      )
      result.each_value do |counts|
        expect(counts.keys).to contain_exactly(:processed, :succeeded, :failed)
      end
    end

    it "raises ConfigurationError when KMS is not configured" do
      # Strip configuration so the precondition guard fires. This guard is the
      # one piece of Backfill that's still operationally relevant post-cutover
      # — if an operator runs the rake task with no CMK configured, we want a
      # loud refusal rather than a silent no-op.
      CredentialVault.kms_client = nil
      CredentialVault.key_arn    = nil
      orig_env = ENV.delete("MYSIGNER_KMS_KEY_ARN")

      expect {
        described_class.run(sleep_seconds: 0, logger: silent_logger)
      }.to raise_error(CredentialVault::ConfigurationError, /MYSIGNER_KMS_KEY_ARN/)
    ensure
      ENV["MYSIGNER_KMS_KEY_ARN"] = orig_env if orig_env
    end

    it "is a no-op for rows that have NULL envelopes (legacy recovery impossible post-cutover)" do
      # Post-mysigner-32, there is no way for a fresh-loaded record to recover
      # plaintext from the AR-encrypted column — the Vaulted accessor reads
      # exclusively from the envelope. A row with envelope=NULL therefore
      # cannot be re-encrypted by Backfill: there's no plaintext source. This
      # spec pins that behavior so an accidental "read from AR column as
      # fallback" reintroduction would be caught immediately.
      cred = create(:app_store_connect_credential, private_key: "PEM-A")
      cred.update_columns(private_key_envelope: nil)

      result = described_class.run(batch_size: 10, sleep_seconds: 0, logger: silent_logger)

      # The row IS visited (it matches the NULL envelope filter), the save
      # succeeds (writes envelope=NULL, a no-op), but no plaintext recovery
      # happens. The envelope stays NULL.
      expect(result[:AppStoreConnectCredential]).to include(processed: 1, succeeded: 1, failed: 0)
      expect(cred.reload.private_key_envelope).to be_nil
    end
  end
end
