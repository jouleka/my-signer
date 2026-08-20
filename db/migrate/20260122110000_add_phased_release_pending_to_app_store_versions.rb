class AddPhasedReleasePendingToAppStoreVersions < ActiveRecord::Migration[8.0]
  def change
    add_column :app_store_versions, :phased_release_pending, :boolean, default: false, null: false
    add_index :app_store_versions, :phased_release_pending,
              where: "phased_release_pending = true",
              name: "index_app_store_versions_on_phased_pending"
  end
end
