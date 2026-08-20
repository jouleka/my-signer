class EnableReleaseHistoryTracking < ActiveRecord::Migration[8.0]
  def up
    remove_index :play_store_releases, name: "index_play_store_releases_on_android_app_id"

    add_column :play_store_releases, :version_code, :string
    add_column :play_store_releases, :status, :string, null: false, default: "draft"
    add_column :play_store_releases, :released_at, :datetime

    execute <<~SQL.squish
      UPDATE play_store_releases
      SET version_code = 'legacy'
      WHERE version_code IS NULL
    SQL
    change_column_null :play_store_releases, :version_code, false

    add_index :play_store_releases,
              [ :android_app_id, :version_code, :status ],
              unique: true,
              name: "index_play_store_releases_on_app_version_status"

    remove_index :app_store_releases, name: "index_app_store_releases_on_bundle_id_unique"

    add_column :app_store_releases, :status, :string, null: false, default: "draft"
    add_column :app_store_releases, :released_at, :datetime

    add_index :app_store_releases,
              [ :apple_bundle_id_id, :version_string, :status ],
              unique: true,
              name: "index_app_store_releases_on_bundle_version_status"
  end

  def down
    remove_index :play_store_releases, name: "index_play_store_releases_on_app_version_status"

    change_column_null :play_store_releases, :version_code, true
    remove_column :play_store_releases, :released_at
    remove_column :play_store_releases, :status
    remove_column :play_store_releases, :version_code

    add_index :play_store_releases, :android_app_id, unique: true

    remove_index :app_store_releases, name: "index_app_store_releases_on_bundle_version_status"

    remove_column :app_store_releases, :released_at
    remove_column :app_store_releases, :status

    add_index :app_store_releases,
              :apple_bundle_id_id,
              unique: true,
              name: "index_app_store_releases_on_bundle_id_unique"
  end
end
