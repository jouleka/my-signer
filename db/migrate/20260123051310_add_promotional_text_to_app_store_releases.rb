class AddPromotionalTextToAppStoreReleases < ActiveRecord::Migration[8.0]
  def change
    add_column :app_store_releases, :promotional_text, :text
  end
end
