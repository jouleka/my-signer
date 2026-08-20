class CreateAndroidTracks < ActiveRecord::Migration[8.0]
  def change
    create_table :android_tracks do |t|
      t.references :android_app, null: false, foreign_key: true
      t.string :track_name, null: false
      t.string :status
      t.jsonb :releases, default: {}
      t.jsonb :raw_json, default: {}
      t.timestamps
    end

    add_index :android_tracks, [ :android_app_id, :track_name ], unique: true
  end
end
