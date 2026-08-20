# Adds the columns CredentialVault needs on google_play_credentials:
#
#   * vault_record_id (UUID, NOT NULL, default gen_random_uuid()) — stable
#     per-record identifier used in the KMS EncryptionContext. DB-level
#     default is a safety net; the Vaulted concern assigns the UUID in Ruby
#     before INSERT.
#
#   * service_account_json_envelope (text, nullable) — holds the packed
#     envelope for the vault-encrypted service-account JSON. Nullable
#     during the dual-write transition; mysigner-28 backfill will populate
#     it for existing rows.
#
# Companion ticket: mysigner-26 (the rest of mysigner-27 follows the same
# pattern for the remaining credential models).
class AddVaultColumnsToGooglePlayCredentials < ActiveRecord::Migration[8.0]
  def up
    add_column :google_play_credentials, :vault_record_id, :uuid, default: -> { "gen_random_uuid()" }
    add_column :google_play_credentials, :service_account_json_envelope, :text

    execute <<~SQL.squish
      UPDATE google_play_credentials
         SET vault_record_id = gen_random_uuid()
       WHERE vault_record_id IS NULL
    SQL

    change_column_null :google_play_credentials, :vault_record_id, false
    add_index :google_play_credentials, :vault_record_id, unique: true
  end

  def down
    remove_index  :google_play_credentials, :vault_record_id
    remove_column :google_play_credentials, :vault_record_id
    remove_column :google_play_credentials, :service_account_json_envelope
  end
end
