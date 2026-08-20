class EnforceUniqueActiveAndroidKeystores < ActiveRecord::Migration[8.0]
  def change
    # One active keystore per (org, app)
    add_index :android_keystores,
              [ :organization_id, :android_app_id ],
              unique: true,
              where: "active = true AND android_app_id IS NOT NULL",
              name: "idx_unique_active_keystore_per_org_app"

    # And at most one active keystore per org for NULL app scope (shared keystore use-case)
    add_index :android_keystores,
              [ :organization_id ],
              unique: true,
              where: "active = true AND android_app_id IS NULL",
              name: "idx_unique_active_keystore_per_org_null_app"
  end
end
