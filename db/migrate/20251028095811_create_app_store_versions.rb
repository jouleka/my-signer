class CreateAppStoreVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :app_store_versions do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :apple_app, null: false, foreign_key: true
      t.references :build, foreign_key: true
      t.string :version_id, null: false
      t.string :version_string
      t.string :platform
      t.string :app_store_state
      t.jsonb :raw_json, default: {}

      t.timestamps
    end

    add_index :app_store_versions, :version_id, unique: true
    add_index :app_store_versions, [ :apple_app_id, :version_string ]
  end
end
