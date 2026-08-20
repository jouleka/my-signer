class CreateAppleCacheTables < ActiveRecord::Migration[8.0]
  def change
    create_table :apple_certificates do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :remote_id, null: false
      t.string :name
      t.string :certificate_type
      t.string :serial_number
      t.string :platform
      t.string :status
      t.datetime :expires_at
      t.jsonb :raw_json
      t.timestamps
    end
    add_index :apple_certificates, [ :organization_id, :remote_id ], unique: true
    add_index :apple_certificates, [ :organization_id, :expires_at ]
    add_index :apple_certificates, [ :organization_id, :platform ]

    create_table :apple_devices do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :remote_id, null: false
      t.string :name
      t.string :udid
      t.string :platform
      t.string :device_class
      t.string :status
      t.datetime :added_at
      t.jsonb :raw_json
      t.timestamps
    end
    add_index :apple_devices, [ :organization_id, :remote_id ], unique: true
    add_index :apple_devices, [ :organization_id, :udid ]
    add_index :apple_devices, [ :organization_id, :platform ]

    create_table :apple_provisioning_profiles do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :remote_id, null: false
      t.string :name
      t.string :uuid
      t.string :profile_type
      t.string :state
      t.string :platform
      t.string :bundle_id_identifier
      t.datetime :expires_at
      t.jsonb :raw_json
      t.timestamps
    end
    add_index :apple_provisioning_profiles, [ :organization_id, :remote_id ], unique: true
    add_index :apple_provisioning_profiles, [ :organization_id, :expires_at ]
    add_index :apple_provisioning_profiles, [ :organization_id, :platform ]
  end
end
