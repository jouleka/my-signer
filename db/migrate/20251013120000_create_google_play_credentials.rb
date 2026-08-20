class CreateGooglePlayCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :google_play_credentials do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name
      t.text :service_account_json
      t.string :developer_account_id
      t.boolean :active, null: false, default: true
      t.datetime :last_synced_at
      t.string :last_sync_status
      t.text :last_sync_error

      t.timestamps
    end

    add_index :google_play_credentials, [ :organization_id, :name ], unique: true
    add_index :google_play_credentials, [ :organization_id, :active ]
  end
end
