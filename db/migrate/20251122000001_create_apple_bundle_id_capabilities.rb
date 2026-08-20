class CreateAppleBundleIdCapabilities < ActiveRecord::Migration[8.0]
  def change
    create_table :apple_bundle_id_capabilities do |t|
      t.references :apple_bundle_id, null: false, foreign_key: true, index: true
      t.string :remote_id, null: false
      t.string :capability_type, null: false
      t.jsonb :settings, default: {}
      t.jsonb :raw_json, default: {}
      t.timestamps

      t.index [ :apple_bundle_id_id, :capability_type ], unique: true, name: "idx_bundle_id_capabilities_unique"
    end
  end
end
