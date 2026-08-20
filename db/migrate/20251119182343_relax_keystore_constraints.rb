class RelaxKeystoreConstraints < ActiveRecord::Migration[8.0]
  def change
    # Remove the constraint that allows only ONE active unassigned key per organization
    # This enables the "Bag of Keys" workflow where an org can upload multiple keys before linking them to apps
    remove_index :android_keystores, name: "idx_unique_active_keystore_per_org_null_app"
  end
end
