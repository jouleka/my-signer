# Backfill existing AR-encrypted credentials into the new vault envelope
# columns. See app/services/credential_vault/backfill.rb for the algorithm.
#
# Operational use:
#   bin/kamal app exec --interactive "bin/rails credential_vault:backfill"
#
# Idempotent — safe to rerun. Skips rows whose envelopes are already populated.
namespace :credential_vault do
  desc "Backfill existing credentials into vault envelope columns (mysigner-28)"
  task backfill: :environment do
    results = CredentialVault::Backfill.run

    puts ""
    puts "CredentialVault backfill complete."
    results.each do |class_name, counts|
      puts "  #{class_name}: processed=#{counts[:processed]} " \
           "succeeded=#{counts[:succeeded]} failed=#{counts[:failed]}"
    end

    any_failures = results.values.any? { |c| c[:failed].positive? }
    if any_failures
      warn "WARNING: some rows failed to backfill — check Rails.logger for details."
      exit 1
    end
  end

  # Pre-flight verification before flipping credential reads from the
  # AR-encrypted columns to the envelope columns (mysigner-32). Replaces a
  # 30-day soak period: instead of waiting to discover broken envelopes at
  # read time, we attempt-decrypt every (row, vault_attr) pair up front.
  # Exits non-zero on any failure so a CI/script invocation surfaces the
  # problem rather than passing silently.
  desc "Verify every credential's envelope decrypts cleanly (mysigner-32)"
  task verify_all_envelopes: :environment do
    started_at = Time.now.utc
    puts "=== CredentialVault envelope verification ==="
    puts "Started: #{started_at.strftime('%Y-%m-%d %H:%M UTC')}"
    puts ""

    results = CredentialVault::EnvelopeVerifier.run

    # Padded label column keeps the report readable when classes have very
    # different name lengths. 26 chars covers AppStoreConnectCredential
    # ("AppStoreConnectCredential:" = 26).
    label_width = 26

    total_checked  = 0
    total_ok       = 0
    total_missing  = 0
    total_failed   = 0
    all_failures   = []

    results.each do |class_name, counts|
      total_checked += counts[:checked]
      total_ok      += counts[:ok]
      total_missing += counts[:missing_envelope]
      total_failed  += counts[:decrypt_failed]
      all_failures.concat(counts[:failures])

      puts format(
        "%-#{label_width}s checked=%-3d ok=%-3d missing=%-3d failed=%-3d",
        "#{class_name}:",
        counts[:checked],
        counts[:ok],
        counts[:missing_envelope],
        counts[:decrypt_failed]
      )
    end

    puts ""
    puts format(
      "TOTAL: checked=%d  ok=%d  missing=%d  failed=%d",
      total_checked, total_ok, total_missing, total_failed
    )

    if all_failures.any?
      puts ""
      puts "=== FAILURES ==="
      all_failures.each do |f|
        puts "  #{f[:class]}##{f[:record_id]} org=#{f[:organization_id]} " \
             "attr=#{f[:attr_name]} #{f[:error_class]}: #{f[:error_message]}"
      end
      warn ""
      warn "ERROR: #{all_failures.size} envelope(s) failed to decrypt. " \
           "Do NOT flip the read path until every failure is resolved."
      exit 1
    end

    puts "=== All envelopes verified ==="
    exit 0
  end
end
