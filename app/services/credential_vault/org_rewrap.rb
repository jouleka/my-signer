# Re-wraps every vaulted credential row in a single organization under a
# specific CMK ARN. The cousin of `CredentialVault::Backfill` — that one
# iterates rows with NULL envelopes across ALL orgs; this one iterates ALL
# rows in ONE org regardless of envelope state.
#
# Used by the `Organization#rewrap_credentials_on_byok_change` before_save
# callback whenever `byok_kms_key_arn` changes:
#
#   - Register (nil → ARN):    re-wrap under the customer's CMK.
#   - Clear   (ARN → nil):     re-wrap back under the env-default CMK.
#   - Migrate (ARN_a → ARN_b): re-wrap under the new customer CMK.
#
# `key_arn` is passed explicitly (NOT read from `organization.byok_kms_key_arn`)
# so the caller controls which CMK to use. Inside the org's own before_save,
# `byok_kms_key_arn` already holds the NEW value being saved — but the
# callback may need to re-wrap with EITHER the new value (register/migrate)
# or nil (clear). The caller resolves that ambiguity once and passes the
# concrete ARN in.
#
# Per-row write strategy: `update_column` (NOT `save`). `save` would re-fire
# the Vaulted before_save, which would re-read `organization.byok_kms_key_arn`
# on the in-memory record — but that value may not be the one we want to
# encrypt with at this point in the org's save lifecycle. `update_column`
# writes the envelope column directly without re-triggering callbacks.
#
# Atomicity: AR wraps `before_save` callbacks in the same transaction as the
# org save. If the callback throws :abort, every `update_column` write
# OrgRewrap issued rolls back along with the org row. External side effects
# (KMS round-trips for the credentials before the failing one) are NOT
# rolled back — they're already billed to the customer's CloudTrail and
# the DEKs produced get discarded along with the rolled-back envelopes
# (mysigner-21).
#
# IMPORTANT — no per-row rescue. Unlike `Backfill` (operator-driven, best-effort,
# logs per-row failures and continues), this class is user-driven and must be
# atomic: a KMS failure on the Nth credential MUST propagate up so the
# `Organization#rewrap_credentials_on_byok_change` callback can throw :abort
# and the AR transaction can roll back every `update_column` write issued for
# credentials 1..N-1. Swallowing exceptions here would silently commit a
# partial re-wrap and break the "all-or-nothing DB" contract. Exceptions
# propagate; the org callback handles the `Aws::KMS::Errors::ServiceError`
# case with a user-friendly model error, and any other class bubbles to the
# controller and rolls the transaction back via standard AR semantics.
#
# Companion ticket: mysigner-21 sub-ticket 2.3.
class CredentialVault
  class OrgRewrap
    # Reuse Backfill's class list — the four credential models that mix in
    # Vaulted. Keeping a single source of truth means a future fifth
    # credential kind only has to be added in one place.
    TARGETS = CredentialVault::Backfill::TARGETS

    # @param organization [Organization] the org whose credentials get re-wrapped
    # @param key_arn [String, nil] explicit CMK ARN to wrap with. nil falls
    #   back to the env-default CMK (the "clear" path).
    # @param logger [#info, #error] something logger-shaped
    # @return [Hash{Symbol=>Hash}] counts per model class, e.g.
    #   { AppStoreConnectCredential: { processed:, succeeded: }, ... }
    #   `processed` counts ROWS visited (matching Backfill's semantics);
    #   `succeeded` counts rows that completed iteration without raising. In
    #   the no-failure path these are always equal; if iteration raises,
    #   no hash is returned (the exception propagates).
    def self.run(organization:, key_arn:, logger: Rails.logger)
      results = {}

      TARGETS.each do |class_name|
        klass = class_name.constantize
        counts = rewrap_class(klass, organization, key_arn, logger)
        results[klass.name.to_sym] = counts
        logger.info(
          "[CredentialVault::OrgRewrap] org=#{organization.id} #{klass.name}: " \
          "processed=#{counts[:processed]} succeeded=#{counts[:succeeded]}"
        )
      end

      results
    end

    # Re-wrap every vault-managed attribute on every row of +klass+ in +organization+.
    # `processed` counts ROWS (not attrs) for consistency with `Backfill`. Any
    # exception inside the inner loop propagates — see the class docstring.
    def self.rewrap_class(klass, organization, key_arn, _logger)
      processed = 0
      succeeded = 0

      klass.where(organization_id: organization.id).find_each do |record|
        processed += 1

        klass.vault_attrs.each do |attr_name, config|
          # Capture the OLD envelope (if any) BEFORE we overwrite it, so we can
          # evict its cached plaintext DEK from the process-local cache once the
          # re-wrap lands (L-1). Reading the raw envelope column avoids
          # triggering a decrypt here.
          old_packed = record.read_attribute(config[:envelope_column])

          plaintext = record.public_send(attr_name)
          # Skip attrs whose plaintext is nil — there's nothing to wrap.
          # The row is in a valid state, it just doesn't have an envelope
          # to re-target.
          next if plaintext.nil?

          # L-25: use the single shared context builder (also enforces the
          # L-20 blank-vault_record_id guard) instead of hand-building it here.
          context = klass.context_for(record: record, kind: config[:kind])
          envelope = CredentialVault.encrypt(plaintext.to_s, context: context, key_arn: key_arn)
          record.update_column(config[:envelope_column], CredentialVault.pack(envelope))

          # L-1: now that the row points at the NEW wrapped DEK, drop the OLD
          # wrapped DEK's cached plaintext from RAM so a key we just rotated
          # away (e.g. a BYOK migrate/clear) can't keep serving decrypts until
          # its TTL lapses. Best-effort + non-fatal: a failure to evict must
          # not roll back the (already-committed via update_column) re-wrap.
          evict_old_dek(old_packed)
        end

        succeeded += 1
      end

      { processed: processed, succeeded: succeeded }
    end

    # L-1: evict the OLD wrapped DEK's cached plaintext from the process-local
    # DEK cache. `old_packed` is the JSON envelope string previously stored in
    # the column (or nil/blank for a row that had no envelope yet). Best-effort:
    # any failure to unpack a malformed legacy envelope, or to evict, is
    # swallowed — the re-wrap itself has already succeeded and an eviction miss
    # only means the entry lingers until its (short, for BYOK) TTL.
    def self.evict_old_dek(old_packed)
      return if old_packed.blank?

      old = CredentialVault.unpack(old_packed)
      CredentialVault.evict_dek(old.wrapped_dek, old.key_id)
    rescue => e
      Rails.logger.warn(
        "[CredentialVault::OrgRewrap] DEK eviction skipped (non-fatal): #{e.class}: #{e.message}"
      )
      nil
    end
  end
end
