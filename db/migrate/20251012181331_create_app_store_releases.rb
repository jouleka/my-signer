class CreateAppStoreReleases < ActiveRecord::Migration[8.0]
  def change
    create_table :app_store_releases do |t|
      t.references :apple_bundle_id, null: false, foreign_key: true, index: true

      # Release metadata
      t.text :whats_new
      t.string :support_url
      t.string :marketing_url
      t.string :privacy_policy_url

      # Submission settings
      t.boolean :auto_submit, default: false, null: false
      t.boolean :phased_release, default: false, null: false

      # Version tracking (optional, for reference)
      t.string :version_string
      t.string :build_number

      # Localizations (future: multi-language support)
      t.jsonb :localizations, default: {}

      t.timestamps
    end

    # Ensure one release config per bundle ID (can be removed if we want version history)
    add_index :app_store_releases, :apple_bundle_id_id, unique: true, name: "index_app_store_releases_on_bundle_id_unique"
  end
end
