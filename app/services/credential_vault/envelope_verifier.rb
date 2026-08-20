# Pre-flight verification that every existing credential's envelope decrypts
# cleanly under the current KMS configuration (mysigner-32 sister to the
# read-path flip).
#
# Why this exists: when we flip credential reads from the Active Record
# encrypted columns to the envelope columns, a row whose envelope is missing
# or undecryptable goes from "works fine" to "silently broken at use time".
# This task proves — before the flip — that every (row, vault_attr) pair
# either has no envelope yet (legacy / nil plaintext — acceptable) or
# decrypts cleanly. A non-zero `decrypt_failed` count is a hard stop.
#
# Algorithm per model class:
#   1. For every row of the class, for every entry in `vault_attrs`:
#      a. Read the envelope JSON via `read_attribute(envelope_column)`.
#      b. If blank: count as `missing_envelope` and move on. The backfill
#         deliberately skips rows whose plaintext is nil; a nil envelope on
#         a row with no plaintext is the expected steady state, not a bug.
#      c. Else: unpack + decrypt, using the same context shape that
#         `Vaulted#vault_context` writes at encrypt time. Success counts as
#         `ok`. Any exception counts as `decrypt_failed` and is recorded
#         in `failures` with full per-row context.
#   2. Continue past every failure — the goal is a complete report, not a
#      first-error abort. A CI/operator-driven caller can read the result
#      hash, surface every broken row at once, and decide whether to fix
#      and re-run or hold the flip.
#
# Companion to:
#   - `CredentialVault::Backfill` (writes envelopes for legacy rows)
#   - `CredentialVault::OrgRewrap`  (rotates envelopes under a different CMK)
#
# Operationally: run via Rake from a Kamal console:
#   bin/kamal app exec --interactive "bin/rails credential_vault:verify_all_envelopes"
class CredentialVault
  class EnvelopeVerifier
    # Reuse Backfill's class list — the four credential models that mix in
    # Vaulted. Sharing the list means a future fifth credential kind only
    # has to be registered in one place (Backfill::TARGETS).
    TARGETS = CredentialVault::Backfill::TARGETS

    # @param logger [#info, #error] something logger-shaped
    # @return [Hash{Symbol=>Hash}] counts + failure detail per model class:
    #   {
    #     AppStoreConnectCredential: {
    #       checked: N, ok: N, missing_envelope: N, decrypt_failed: N,
    #       failures: [ {class:, record_id:, organization_id:,
    #                    attr_name:, error_class:, error_message:}, ... ]
    #     },
    #     ...
    #   }
    #
    # Invariant: `checked == ok + missing_envelope + decrypt_failed` per class.
    def self.run(logger: Rails.logger)
      results = {}

      TARGETS.each do |class_name|
        klass = class_name.constantize
        counts = verify_class(klass, logger)
        results[klass.name.to_sym] = counts
        logger.info(
          "[CredentialVault::EnvelopeVerifier] #{klass.name}: " \
          "checked=#{counts[:checked]} ok=#{counts[:ok]} " \
          "missing_envelope=#{counts[:missing_envelope]} " \
          "decrypt_failed=#{counts[:decrypt_failed]}"
        )
      end

      results
    end

    # Verify every vault-managed envelope on every row of +klass+.
    # Iterates per-row + per-attr. Never aborts on failure.
    def self.verify_class(klass, logger)
      checked          = 0
      ok               = 0
      missing_envelope = 0
      decrypt_failed   = 0
      failures         = []

      # Preload :organization to keep parity with Backfill, in case a future
      # rev of Vaulted reads org-level state during decrypt context build.
      klass.includes(:organization).find_each do |record|
        klass.vault_attrs.each do |attr_name, config|
          checked += 1
          envelope_json = record.read_attribute(config[:envelope_column])

          if envelope_json.blank?
            # Backfill deliberately skips rows whose plaintext is nil — so
            # a NULL envelope is the expected steady state for those rows,
            # not a failure to report.
            missing_envelope += 1
            next
          end

          begin
            envelope = CredentialVault.unpack(envelope_json)
            # L-25: use the single shared context builder (matches exactly what
            # Vaulted#vault_context wrote at encrypt time, and enforces the
            # L-20 blank-vault_record_id guard) instead of hand-building it here.
            context = klass.context_for(record: record, kind: config[:kind])
            # audit: false — this is an operational pre-flight sweep, not a
            # credential "use", so it must not flood the audit log or incur a
            # per-record org lookup (the find_each above already preloads org).
            CredentialVault.decrypt(envelope, context: context, audit: false)
            ok += 1
          rescue => e
            # Broad rescue is intentional. The expected failure modes are
            # `DecryptError`, `CustomerKeyRevoked`, `Aws::KMS::Errors::*`,
            # `JSON::ParserError` (corrupt envelope JSON), and `KeyError`
            # (missing field after unpack). All of them are equally
            # disqualifying for the read-path flip, so we record them all
            # with the same shape and keep iterating — the caller wants
            # the complete failure set, not the first one.
            decrypt_failed += 1
            failure = {
              class:           klass.name,
              record_id:       record.id,
              organization_id: record.organization_id,
              attr_name:       attr_name,
              error_class:     e.class.name,
              error_message:   e.message
            }
            failures << failure
            logger.error(
              "[CredentialVault::EnvelopeVerifier] #{klass.name}/#{record.id} " \
              "#{attr_name}: #{e.class}: #{e.message}"
            )
          end
        end
      end

      {
        checked:          checked,
        ok:               ok,
        missing_envelope: missing_envelope,
        decrypt_failed:   decrypt_failed,
        failures:         failures
      }
    end
  end
end
