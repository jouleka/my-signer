# Encrypts existing AR-encrypted credentials into the new vault envelope
# columns (mysigner-28).
#
# Before this runs, all four credential models have been migrated to dual-write
# (mysigner-26): new rows get their envelope columns populated by the Vaulted
# concern's `before_save` callback. But rows that existed before the dual-write
# shipped don't have envelopes yet — that's what this backfills.
#
# Algorithm per model class:
#   1. Find every row where ANY of the vault-managed envelope columns is NULL.
#   2. Call `save!(validate: false)`. The Vaulted concern's before_save chain
#      reads the AR-encrypted plaintext via the public accessor and writes the
#      packed envelope to the corresponding column.
#   3. Validations are skipped because backfill must succeed even if the
#      row's business validation rules have evolved since it was inserted.
#      We're not changing any user-visible attribute — just mirroring the
#      already-stored plaintext through KMS.
#
# Idempotent: rerunning will skip rows whose envelopes are all populated
# (the per-attribute `will_save_change_to_attribute? || envelope.blank?` guard
# in Vaulted#sync_one_vaulted_envelope handles this).
#
# Operationally: run via Rake from a Kamal console:
#   bin/kamal app exec --interactive "bin/rails credential_vault:backfill"
class CredentialVault
  class Backfill
    # All four credential models that use the Vaulted concern. Order doesn't
    # matter functionally; we go alphabetically for predictable logs.
    TARGETS = %w[
      AndroidKeystore
      AppleAdsCredential
      AppStoreConnectCredential
      GooglePlayCredential
    ].freeze

    # @param batch_size [Integer] rows per in_batches iteration
    # @param sleep_seconds [Numeric] sleep between batches (gentle on KMS)
    # @param logger [#info, #error] something logger-shaped
    # @return [Hash{Symbol=>Integer}] counts per model class
    def self.run(batch_size: 100, sleep_seconds: 0.5, logger: Rails.logger)
      unless CredentialVault.configured?
        raise CredentialVault::ConfigurationError,
              "Cannot backfill — MYSIGNER_KMS_KEY_ARN is not set."
      end

      results = {}

      TARGETS.each do |class_name|
        klass = class_name.constantize
        counts = backfill_class(klass, batch_size, sleep_seconds, logger)
        results[klass.name.to_sym] = counts
        logger.info(
          "[CredentialVault::Backfill] #{klass.name}: " \
          "processed=#{counts[:processed]} succeeded=#{counts[:succeeded]} failed=#{counts[:failed]}"
        )
      end

      results
    end

    # Backfill a single model class. Returns counts hash.
    def self.backfill_class(klass, batch_size, sleep_seconds, logger)
      envelope_columns = klass.vault_attrs.values.map { |v| v[:envelope_column] }
      return { processed: 0, succeeded: 0, failed: 0 } if envelope_columns.empty?

      # Find rows where AT LEAST ONE envelope column is null.
      null_predicate = envelope_columns.map { |col| "#{col} IS NULL" }.join(" OR ")

      processed = 0
      succeeded = 0
      failed    = 0

      # Preload :organization to avoid N+1 — the Vaulted concern reads
      # `organization.byok_kms_key_arn` during each before_save (mysigner-21
      # sub-ticket 2.3), so a bulk backfill over N rows without this
      # would issue N extra SELECTs against `organizations`.
      klass.where(null_predicate).includes(:organization).in_batches(of: batch_size) do |batch|
        batch.each do |record|
          processed += 1
          begin
            # validate: false because backfill must succeed even if business
            # validations have changed since the row was inserted. We're not
            # altering user data — just mirroring already-stored plaintext.
            record.save!(validate: false)
            succeeded += 1
          rescue => e
            failed += 1
            logger.error(
              "[CredentialVault::Backfill] #{klass.name}/#{record.id}: #{e.class}: #{e.message}"
            )
          end
        end
        sleep(sleep_seconds) if sleep_seconds.positive?
      end

      { processed: processed, succeeded: succeeded, failed: failed }
    end
  end
end
