class RenameBuildsToAppleBuilds < ActiveRecord::Migration[8.0]
  def change
    rename_table :builds, :apple_builds

    # Rename the foreign key column in app_store_versions
    rename_column :app_store_versions, :build_id, :apple_build_id
  end
end
