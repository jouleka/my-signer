class CreateBuilds < ActiveRecord::Migration[8.0]
  def change
    create_table :builds do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :apple_app, null: false, foreign_key: true
      t.string :build_id, null: false
      t.string :version
      t.string :build_number
      t.string :processing_state
      t.datetime :uploaded_date
      t.datetime :expires_at
      t.jsonb :raw_json, default: {}

      t.timestamps
    end

    add_index :builds, :build_id, unique: true
    add_index :builds, [ :apple_app_id, :version, :build_number ]
  end
end
