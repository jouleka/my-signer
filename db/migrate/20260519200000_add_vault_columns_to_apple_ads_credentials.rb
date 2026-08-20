# Adds the columns CredentialVault needs on apple_ads_credentials:
#
#   * vault_record_id (UUID, NOT NULL, default gen_random_uuid()) — stable
#     per-record identifier used in the KMS EncryptionContext.
#
#   * private_key_pem_envelope (text, nullable) — packed envelope of the
#     vault-encrypted Apple Search Ads EC private key.
#
# Only the private_key_pem field is vaulted on this model. The identifiers
# (client_id, team_id, key_id) stay on Rails Active Record Encryption —
# they're identifiers, not signing material, and the deterministic-encrypted
# ones need to stay queryable.
#
# Companion ticket: mysigner-26.
class AddVaultColumnsToAppleAdsCredentials < ActiveRecord::Migration[8.0]
  def up
    add_column :apple_ads_credentials, :vault_record_id, :uuid, default: -> { "gen_random_uuid()" }
    add_column :apple_ads_credentials, :private_key_pem_envelope, :text

    execute <<~SQL.squish
      UPDATE apple_ads_credentials
         SET vault_record_id = gen_random_uuid()
       WHERE vault_record_id IS NULL
    SQL

    change_column_null :apple_ads_credentials, :vault_record_id, false
    add_index :apple_ads_credentials, :vault_record_id, unique: true
  end

  def down
    remove_index  :apple_ads_credentials, :vault_record_id
    remove_column :apple_ads_credentials, :vault_record_id
    remove_column :apple_ads_credentials, :private_key_pem_envelope
  end
end
