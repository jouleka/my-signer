class CreateTrialHistories < ActiveRecord::Migration[8.0]
  def change
    # Tracks which email addresses have ever started a reverse trial.
    # Persists across User deletions so re-registering with the same email
    # doesn't grant a second trial.
    #
    # Emails are stored as SHA-256 hashes (normalized to lowercase) to
    # minimize PII retention while still supporting presence checks. The
    # hash is irreversible but deterministic for a given input -- "an
    # attacker with the DB can tell if a specific email has had a trial,
    # but cannot enumerate emails from the table alone."
    create_table :trial_histories do |t|
      t.string   :email_hash, null: false
      t.datetime :started_at, null: false
      t.timestamps
    end

    add_index :trial_histories, :email_hash, unique: true
  end
end
