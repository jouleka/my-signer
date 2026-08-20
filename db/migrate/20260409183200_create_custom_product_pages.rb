class CreateCustomProductPages < ActiveRecord::Migration[8.0]
  def change
    create_table :custom_product_pages do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :apple_app, null: false, foreign_key: true
      t.string :remote_id, null: false
      t.string :name, null: false
      t.boolean :visible, null: false, default: true
      t.jsonb :raw_json, default: {}
      t.jsonb :performance_data, default: {}
      t.datetime :performance_synced_at
      t.timestamps
    end
    add_index :custom_product_pages, :remote_id, unique: true
    add_index :custom_product_pages, [ :apple_app_id, :name ]
  end
end
