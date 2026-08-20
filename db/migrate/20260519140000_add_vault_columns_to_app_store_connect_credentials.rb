# Adds the two columns the CredentialVault needs on app_store_connect_credentials:
#
#   * vault_record_id (UUID, NOT NULL, unique) — stable per-record identifier
#     used as `credential_id` in the KMS EncryptionContext. Decoupled from the
#     primary key so encryption can happen on attribute assignment (no need to
#     wait until after INSERT to know the id). Backfilled with gen_random_uuid()
#     for existing rows in this migration.
#
#   * private_key_envelope (text, nullable) — holds the packed envelope
#     (JSON + base64) for the vault-encrypted private key. Nullable for the
#     dual-write transition: existing rows still read from the AR-encrypted
#     `private_key` column until the mysigner-28 backfill populates this.
#
# Companion ticket: mysigner-26. Production runs Postgres 16, which ships
# gen_random_uuid() in core — no pgcrypto extension required.
class AddVaultColumnsToAppStoreConnectCredentials < ActiveRecord::Migration[8.0]
  def up
    # 1. Add both columns. `vault_record_id` gets a DB-level default of
    #    gen_random_uuid() so that any INSERT that doesn't explicitly assign
    #    one still gets a UUID — defensive against the deploy-window scenario
    #    where this migration ships before the Vaulted concern that's
    #    supposed to assign the UUID in Ruby (next commit). Once the concern
    #    is live, the app assigns the UUID before INSERT and the default
    #    never kicks in; the default is purely a safety net.
    #    `private_key_envelope` stays nullable for the dual-write transition
    #    (mysigner-28 backfill populates it for existing rows).
    add_column :app_store_connect_credentials, :vault_record_id, :uuid, default: -> { "gen_random_uuid()" }
    add_column :app_store_connect_credentials, :private_key_envelope, :text

    # 2. Backfill vault_record_id for every existing row before tightening
    #    the NOT NULL constraint. Single UPDATE — fine for the table sizes
    #    we expect; revisit batching if this grows past ~100k rows.
    execute <<~SQL.squish
      UPDATE app_store_connect_credentials
         SET vault_record_id = gen_random_uuid()
       WHERE vault_record_id IS NULL
    SQL

    # 3. Enforce stability constraints now that all rows have a value.
    change_column_null :app_store_connect_credentials, :vault_record_id, false
    add_index :app_store_connect_credentials, :vault_record_id, unique: true
  end

  def down
    remove_index  :app_store_connect_credentials, :vault_record_id
    remove_column :app_store_connect_credentials, :vault_record_id
    remove_column :app_store_connect_credentials, :private_key_envelope
  end
end
