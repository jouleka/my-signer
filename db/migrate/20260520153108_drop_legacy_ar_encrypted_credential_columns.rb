# mysigner-33: drop the legacy Rails-AR-encrypted columns on the four credential
# tables. After mysigner-32 the application stopped reading and writing them;
# the columns sat in the schema for one release as a rollback window. That
# window is now closed.
#
# All four credential models read/write exclusively through their
# `<attr>_envelope` columns via the `Vaulted` concern.
#
# `down` re-adds the columns as nullable so the schema is restorable, but the
# data does NOT come back. Re-running mysigner-32's pre-flight verifier and
# the BYOK backfill would re-populate the envelope columns, but the legacy
# AR-encrypted ciphertext can't be regenerated without the AR keyring + the
# original plaintexts. Treat this migration as a point of no return for the
# AR ciphertext.
class DropLegacyArEncryptedCredentialColumns < ActiveRecord::Migration[8.0]
  def up
    remove_column :app_store_connect_credentials, :private_key
    remove_column :google_play_credentials,       :service_account_json
    remove_column :android_keystores,             :keystore_file
    remove_column :android_keystores,             :keystore_password
    remove_column :android_keystores,             :key_password
    remove_column :apple_ads_credentials,         :private_key_pem
  end

  def down
    # Restore the original column types as nullable. Data is unrecoverable.
    add_column :app_store_connect_credentials, :private_key,          :text
    add_column :google_play_credentials,       :service_account_json, :text
    add_column :android_keystores,             :keystore_file,        :binary
    add_column :android_keystores,             :keystore_password,    :string
    add_column :android_keystores,             :key_password,         :string
    add_column :apple_ads_credentials,         :private_key_pem,      :text
  end
end
