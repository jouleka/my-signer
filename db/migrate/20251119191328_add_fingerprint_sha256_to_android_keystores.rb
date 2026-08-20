class AddFingerprintSha256ToAndroidKeystores < ActiveRecord::Migration[8.0]
  def change
    add_column :android_keystores, :fingerprint_sha256, :string
    add_index :android_keystores, [ :organization_id, :fingerprint_sha256 ], unique: true, name: 'idx_android_keystores_org_fingerprint_unique'
  end
end
