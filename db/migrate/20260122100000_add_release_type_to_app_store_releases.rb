class AddReleaseTypeToAppStoreReleases < ActiveRecord::Migration[8.0]
  def change
    add_column :app_store_releases, :release_type, :string, default: "AFTER_APPROVAL", null: false
    add_column :app_store_releases, :earliest_release_date, :datetime

    # Only add partial index for scheduled releases which need date lookups
    # No index on release_type itself (only 3 values = low cardinality = useless, adds write overhead)
    add_index :app_store_releases, :earliest_release_date,
              where: "release_type = 'SCHEDULED'",
              name: "index_app_store_releases_on_scheduled_date"
  end
end
