class AddAppleBundleIds < ActiveRecord::Migration[8.0]
  def change
    create_table :apple_bundle_ids do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :remote_id, null: false
      t.string :identifier
      t.string :name
      t.string :platform
      t.jsonb :raw_json
      t.timestamps
    end
    add_index :apple_bundle_ids, [ :organization_id, :remote_id ], unique: true
    add_index :apple_bundle_ids, [ :organization_id, :identifier ]
  end
end
