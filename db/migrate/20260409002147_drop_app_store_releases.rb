class DropAppStoreReleases < ActiveRecord::Migration[8.0]
  # Drops the legacy app_store_releases table (and its backup companion)
  # after the cli_defaults backfill migration has moved all data onto
  # apple_apps.cli_defaults. The model, controllers, views, and specs
  # have already been migrated to read/write from the JSONB column.
  #
  # #down is irreversible — the table schema is recreated but rows are
  # NOT restored (the backfill would need to be replayed in reverse,
  # which is not meaningful given the content fields have also moved
  # to StoreListing). Rolling back this migration drops you into a
  # state where the Rails app boots but any already-deployed code that
  # still references AppStoreRelease would fail until redeployed.

  def up
    if foreign_key_exists?(:app_store_releases, :apple_bundle_ids)
      remove_foreign_key :app_store_releases, :apple_bundle_ids
    end

    drop_table :app_store_releases if table_exists?(:app_store_releases)
    drop_table :app_store_releases_backup if table_exists?(:app_store_releases_backup)
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "DropAppStoreReleases is irreversible — the legacy data has been moved to " \
          "apple_apps.cli_defaults (see AddCliDefaultsToAppleApps). Rolling back this " \
          "migration would not restore the original rows."
  end
end
