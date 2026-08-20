class HardenAppStoreConnectCredentials < ActiveRecord::Migration[8.0]
  def change
    change_table :app_store_connect_credentials do |t|
      t.boolean  :active, null: false, default: true
      t.datetime :last_synced_at
      t.string   :last_sync_status
      t.text     :last_sync_error
    end

    add_index :app_store_connect_credentials, [ :organization_id, :active ], name: "index_asc_credentials_on_org_and_active"
    add_index :app_store_connect_credentials, [ :organization_id, :name ], unique: true, name: "index_asc_credentials_on_org_and_name"
  end
end
