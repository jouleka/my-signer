class CreateAscBuildUploads < ActiveRecord::Migration[8.0]
  def change
    create_table :asc_build_uploads do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :apple_app,    null: false, foreign_key: true
      t.references :user,         null: false, foreign_key: true
      t.string :remote_id,                        null: false
      t.string :remote_file_id,                   null: false
      t.string :cf_bundle_version,                null: false
      t.string :cf_bundle_short_version_string,   null: false
      t.string :platform,                         null: false
      t.string :file_name,                        null: false
      t.bigint :file_size,                        null: false
      t.string :state,                            null: false, default: "pending"
      t.string :apple_state
      t.jsonb  :apple_state_detail,               default: {}
      t.string :last_error
      t.datetime :uploaded_at
      t.timestamps

      t.index [ :organization_id, :created_at ]
      t.index :remote_id, unique: true
      t.index [ :organization_id, :apple_app_id, :cf_bundle_version, :state ],
              name: "idx_unique_pending_asc_upload_per_app_version",
              unique: true,
              where: "state = 'pending'"
    end
  end
end
