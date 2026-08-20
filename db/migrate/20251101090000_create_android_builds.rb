class CreateAndroidBuilds < ActiveRecord::Migration[8.0]
  def change
    create_table :android_builds do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :android_app, null: false, foreign_key: true
      t.string :version_code, null: false
      t.string :version_name
      t.string :binary_sha256
      t.string :binary_sha1
      t.string :status
      t.integer :minimum_sdk_version
      t.integer :target_sdk_version
      t.jsonb :native_code, default: []
      t.bigint :file_size_bytes
      t.datetime :uploaded_at
      t.jsonb :raw_json, default: {}

      t.timestamps
    end

    add_index :android_builds, [ :organization_id, :android_app_id ]
    add_index :android_builds, [ :android_app_id, :version_code ], unique: true
  end
end
