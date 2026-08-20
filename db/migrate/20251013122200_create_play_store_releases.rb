class CreatePlayStoreReleases < ActiveRecord::Migration[8.0]
  def change
    create_table :play_store_releases do |t|
      t.references :android_app, null: false, foreign_key: true, index: { unique: true }
      t.string :track, default: 'beta'
      t.text :release_notes
      t.string :status_url
      t.float :user_fraction
      t.boolean :auto_submit, default: false
      t.jsonb :localizations, default: {}
      t.timestamps
    end
  end
end
