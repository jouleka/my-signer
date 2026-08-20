class CreateAppleApps < ActiveRecord::Migration[8.0]
  def change
    create_table :apple_apps do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :app_store_id, null: false
      t.string :bundle_id
      t.string :name
      t.string :sku
      t.jsonb :raw_json, default: {}

      t.timestamps
    end

    add_index :apple_apps, :app_store_id, unique: true
    add_index :apple_apps, [ :organization_id, :bundle_id ]
    add_index :apple_apps, [ :organization_id, :sku ], unique: true
  end
end
