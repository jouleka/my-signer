# frozen_string_literal: true

# Phase 4: Atomic migration for consolidation, backup, and cleanup
# This migration:
# 1. Creates a backup of app_store_releases before making changes
# 2. Handles duplicates by keeping only the most recent per bundle_id
# 3. Adds unique constraint on apple_bundle_id_id (one release config per app)
# 4. Removes obsolete status/released_at columns
# 5. Cleans up old status-based index
class ConsolidateAndCleanupAppStoreReleases < ActiveRecord::Migration[8.0]
  def up
    # Step 1: Create backup table with all data
    execute <<~SQL
      CREATE TABLE app_store_releases_backup AS
      SELECT * FROM app_store_releases;
    SQL
    say "Created backup table: app_store_releases_backup"

    # Step 2: Check for and handle duplicates (keep most recently updated)
    duplicates = execute(<<~SQL).to_a
      SELECT apple_bundle_id_id, COUNT(*) as count
      FROM app_store_releases
      GROUP BY apple_bundle_id_id
      HAVING COUNT(*) > 1;
    SQL

    if duplicates.any?
      say "Found #{duplicates.size} bundle_ids with multiple releases - keeping most recent"

      # Delete all but the most recent per bundle_id
      execute <<~SQL
        DELETE FROM app_store_releases
        WHERE id NOT IN (
          SELECT DISTINCT ON (apple_bundle_id_id) id
          FROM app_store_releases
          ORDER BY apple_bundle_id_id, updated_at DESC
        );
      SQL

      deleted_count = duplicates.sum { |d| d['count'].to_i - 1 }
      say "Removed #{deleted_count} duplicate release(s)"
    else
      say "No duplicate releases found"
    end

    # Step 3: Remove old composite index (status no longer used)
    if index_exists?(:app_store_releases, [ :apple_bundle_id_id, :version_string, :status ], name: "index_app_store_releases_on_bundle_version_status")
      remove_index :app_store_releases, name: "index_app_store_releases_on_bundle_version_status"
      say "Removed old composite index on bundle_version_status"
    end

    # Step 4: Add unique constraint on apple_bundle_id_id (one config per app)
    unless index_exists?(:app_store_releases, :apple_bundle_id_id, unique: true, name: "index_app_store_releases_on_bundle_id_unique")
      add_index :app_store_releases, :apple_bundle_id_id,
                unique: true,
                name: "index_app_store_releases_on_bundle_id_unique"
      say "Added unique constraint on apple_bundle_id_id"
    end

    # Step 5: Remove obsolete columns
    if column_exists?(:app_store_releases, :status)
      remove_column :app_store_releases, :status
      say "Removed status column"
    end

    if column_exists?(:app_store_releases, :released_at)
      remove_column :app_store_releases, :released_at
      say "Removed released_at column"
    end

    say "Migration complete. Backup preserved in app_store_releases_backup table."
  end

  def down
    # Step 1: Remove unique constraint
    if index_exists?(:app_store_releases, :apple_bundle_id_id, name: "index_app_store_releases_on_bundle_id_unique")
      remove_index :app_store_releases, name: "index_app_store_releases_on_bundle_id_unique"
    end

    # Step 2: Re-add status column
    unless column_exists?(:app_store_releases, :status)
      add_column :app_store_releases, :status, :string, default: "draft", null: false
    end

    # Step 3: Re-add released_at column
    unless column_exists?(:app_store_releases, :released_at)
      add_column :app_store_releases, :released_at, :datetime
    end

    # Step 4: Restore composite index
    unless index_exists?(:app_store_releases, [ :apple_bundle_id_id, :version_string, :status ])
      add_index :app_store_releases, [ :apple_bundle_id_id, :version_string, :status ],
                unique: true,
                name: "index_app_store_releases_on_bundle_version_status"
    end

    # Step 5: Restore data from backup if backup table exists
    if table_exists?(:app_store_releases_backup)
      say "Backup table exists. To restore deleted duplicates, manually run:"
      say "  INSERT INTO app_store_releases SELECT * FROM app_store_releases_backup WHERE id NOT IN (SELECT id FROM app_store_releases);"
    end

    # Note: Backup table is NOT dropped in down migration for safety
    say "Rollback complete. Backup table app_store_releases_backup preserved for manual restoration if needed."
  end
end
