class CreateAppleMerchantIds < ActiveRecord::Migration[8.0]
  def change
    create_table :apple_merchant_ids do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :remote_id, null: false        # Apple's ID
      t.string :identifier, null: false       # merchant.com.example.app
      t.string :name
      t.string :team_id
      t.jsonb :raw_json, default: {}
      t.timestamps
    end

    add_index :apple_merchant_ids, [ :organization_id, :remote_id ], unique: true
    add_index :apple_merchant_ids, [ :organization_id, :identifier ], unique: true
    add_index :apple_merchant_ids, [ :organization_id, :team_id ]

    # Join table for Bundle ID associations
    create_table :apple_bundle_id_merchant_ids do |t|
      t.references :apple_bundle_id, null: false, foreign_key: true
      t.references :apple_merchant_id, null: false, foreign_key: true
      t.timestamps
    end

    add_index :apple_bundle_id_merchant_ids, [ :apple_bundle_id_id, :apple_merchant_id_id ],
              unique: true, name: 'idx_bundle_merchant_unique'
  end
end
