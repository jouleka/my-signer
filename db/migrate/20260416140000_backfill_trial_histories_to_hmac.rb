class BackfillTrialHistoriesToHmac < ActiveRecord::Migration[8.0]
  # Switches `trial_histories.email_hash` from plain SHA-256(email) to
  # HMAC-SHA256(secret_key_base, normalized_email). The new normalization
  # also strips the "+tag" subaddress so plus-addressing variants collide
  # to the same hash (closes the trial-bypass loophole).
  #
  # User confirmed only ~4 dev users in production; safe to truncate-and-
  # rebuild. We cannot convert in-place because we never stored the
  # plaintext emails. If we have to roll this back, the data lost is
  # non-essential -- it's just "this email has had a trial; refuse re-
  # entry" markers. Worst case, those ~4 users could re-trial.
  def up
    # Reset all existing rows: they were hashed with plain SHA-256 of
    # whatever-normalization-was-then, and cannot be migrated in place.
    if defined?(TrialHistory) && ActiveRecord::Base.connection.table_exists?(:trial_histories)
      TrialHistory.delete_all
    end

    # Note: User trial markers (trial_started_at / trial_ends_at) are
    # independent state on the User model and are NOT cleared here. The
    # trial_histories table only tracks "this email has had a trial; refuse
    # re-entry."
  end

  def down
    # No-op. Cannot reconstruct the old SHA-256 hashes from the new HMAC
    # hashes (or vice versa) -- both are one-way functions.
  end
end
