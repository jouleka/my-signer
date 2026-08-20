# Adds the columns CredentialVault needs on android_keystores:
#
#   * vault_record_id (UUID, NOT NULL, default gen_random_uuid()) — stable
#     per-record identifier used in the KMS EncryptionContext.
#
#   * keystore_file_envelope     (text, nullable) — packed envelope of the
#     vault-encrypted .jks file bytes
#   * keystore_password_envelope (text, nullable) — packed envelope of the
#     vault-encrypted keystore password
#   * key_password_envelope      (text, nullable) — packed envelope of the
#     vault-encrypted key-entry password
#
# All three envelope columns are nullable for the dual-write transition;
# mysigner-28 backfill will populate them for existing rows.
#
# Companion ticket: mysigner-26.
class AddVaultColumnsToAndroidKeystores < ActiveRecord::Migration[8.0]
  def up
    add_column :android_keystores, :vault_record_id, :uuid, default: -> { "gen_random_uuid()" }
    add_column :android_keystores, :keystore_file_envelope,     :text
    add_column :android_keystores, :keystore_password_envelope, :text
    add_column :android_keystores, :key_password_envelope,      :text

    execute <<~SQL.squish
      UPDATE android_keystores
         SET vault_record_id = gen_random_uuid()
       WHERE vault_record_id IS NULL
    SQL

    change_column_null :android_keystores, :vault_record_id, false
    add_index :android_keystores, :vault_record_id, unique: true
  end

  def down
    remove_index  :android_keystores, :vault_record_id
    remove_column :android_keystores, :vault_record_id
    remove_column :android_keystores, :keystore_file_envelope
    remove_column :android_keystores, :keystore_password_envelope
    remove_column :android_keystores, :key_password_envelope
  end
end
