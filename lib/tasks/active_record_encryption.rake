# mysigner-33 — keyring rotation for Active Record Encryption.
#
# After the legacy AR-encrypted credential columns were dropped, the only
# remaining consumer of Rails AR encryption is SsoConfiguration#idp_cert.
# This task re-encrypts every SsoConfiguration row under the current
# `primary_key`, completing a rotation that was set up by configuring the
# OLD key as `previous` and deploying a new `primary_key`.
#
# Procedure (operator-facing — see mysigner-33):
#
#   1. Generate new keys via `bin/rails db:encryption:init` (capture them).
#   2. Update `.kamal/secrets.d/active_record_encryption_primary_key` to the
#      NEW value; add `.kamal/secrets.d/active_record_encryption_primary_key_previous`
#      with the OLD value.
#   3. `bin/kamal deploy` — the app now decrypts existing rows under the
#      old key (still configured as `previous`) and would encrypt new writes
#      under the new primary.
#   4. `bin/kamal app exec --interactive "bin/rails active_record_encryption:rotate_keyring"`
#      — this task. Re-encrypts every SsoConfiguration row under the new
#      primary.
#   5. Verify a spot-check row decrypts cleanly without the previous key
#      configured (drop the *_PREVIOUS env var, redeploy, read).
#   6. Permanently remove the *_PREVIOUS secret and redeploy.
namespace :active_record_encryption do
  desc "Re-encrypt SsoConfiguration#idp_cert under the current primary key"
  task rotate_keyring: :environment do
    processed = 0
    succeeded = 0
    skipped   = 0

    SsoConfiguration.find_each do |sso|
      processed += 1
      cert = sso.idp_cert

      if cert.blank?
        skipped += 1
        puts "[active_record_encryption:rotate_keyring] skipped SsoConfiguration##{sso.id} (idp_cert is blank)"
        next
      end

      # Force a re-encrypt of an unchanged value: nil-roundtrip inside a
      # transaction so a mid-step failure rolls back both the column nil
      # AND the subsequent re-assignment. update_columns bypasses the AR
      # encryption layer (writes raw nil) and skips callbacks/validations;
      # the subsequent save! re-encrypts under the current primary.
      ActiveRecord::Base.transaction do
        sso.update_columns(idp_cert: nil)
        sso.idp_cert = cert
        sso.save!(validate: false)
      end

      succeeded += 1
      puts "[active_record_encryption:rotate_keyring] re-encrypted SsoConfiguration##{sso.id}"
    end

    puts "[active_record_encryption:rotate_keyring] done: processed=#{processed} succeeded=#{succeeded} skipped=#{skipped}"
  end

  # Deterministic-keyring rotation (follow-up to mysigner-33).
  #
  # Re-encrypts every deterministic AR-encrypted column under the current
  # `deterministic_key`. Used after staging a new deterministic key as
  # current and the OLD value as ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY_PREVIOUS.
  # Unlike the primary key, deterministic encryption has no per-row
  # `previous` fallback for WHERE-clause lookups: until this task finishes,
  # any `find_by(deterministic_col: x)` returns nil for rows still under the
  # old key. Run in a brief maintenance window — these tables hold tens of
  # rows, not millions. Procedure tracked under mysigner-33 (deterministic
  # follow-up).
  desc "Re-encrypt all deterministic-key columns under the current deterministic key"
  task rotate_deterministic_keyring: :environment do
    # Hard-coded model/column list rather than scanning `encrypts` metadata
    # at runtime — a deterministic column added without updating this list
    # would silently stay under the old key after rotation. Forcing the
    # explicit edit makes that mismatch a code-review concern, not a
    # runtime bug. Pre-checks doc tells operators to grep `encrypts :` and
    # confirm this list matches before running.
    targets = {
      "AppStoreConnectCredential" => %i[key_id],
      "AppleAdsCredential"        => %i[client_id team_id],
      "GooglePlayCredential"      => %i[developer_account_id]
    }

    grand_processed = 0
    grand_succeeded = 0
    grand_skipped   = 0

    targets.each do |class_name, det_cols|
      klass = class_name.constantize
      processed = 0
      succeeded = 0
      skipped   = 0

      klass.find_each do |record|
        processed += 1

        # Snapshot every deterministic column on this row in one read pass.
        # Decrypt happens here (via the AR encryption getter), falling back
        # to PREVIOUS if the row is still wrapped under the old key.
        present_cols = det_cols.each_with_object({}) do |col, acc|
          val = record[col]
          acc[col] = val if val.present?
        end

        if present_cols.empty?
          skipped += 1
          puts "[active_record_encryption:rotate_deterministic_keyring] skipped #{class_name}##{record.id} (no deterministic columns set)"
          next
        end

        # All deterministic columns on the row in ONE save — a multi-column
        # model otherwise sits briefly with a mix of old- and new-key
        # ciphertexts on the same row, breaking uniqueness assumptions that
        # span columns. Transactional nil-roundtrip mirrors `rotate_keyring`:
        # if save! raises, the update_columns nil-out rolls back and the
        # original ciphertext survives.
        ActiveRecord::Base.transaction do
          record.update_columns(**present_cols.transform_values { nil })
          present_cols.each { |col, val| record[col] = val }
          record.save!(validate: false)
        end

        succeeded += 1
        puts "[active_record_encryption:rotate_deterministic_keyring] re-encrypted #{class_name}##{record.id} (#{present_cols.keys.join(", ")})"
      end

      puts "[active_record_encryption:rotate_deterministic_keyring] #{class_name} done: processed=#{processed} succeeded=#{succeeded} skipped=#{skipped}"
      grand_processed += processed
      grand_succeeded += succeeded
      grand_skipped   += skipped
    end

    puts "[active_record_encryption:rotate_deterministic_keyring] total: processed=#{grand_processed} succeeded=#{grand_succeeded} skipped=#{grand_skipped}"
  end
end
