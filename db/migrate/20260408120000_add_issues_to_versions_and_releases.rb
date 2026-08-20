class AddIssuesToVersionsAndReleases < ActiveRecord::Migration[8.0]
  def change
    add_column :app_store_versions, :issues, :jsonb, null: false, default: []
    add_column :play_store_releases, :issues, :jsonb, null: false, default: []
    add_column :app_store_versions, :issues_synced_at, :datetime
    add_column :play_store_releases, :issues_synced_at, :datetime
  end
end
