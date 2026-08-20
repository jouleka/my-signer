class AddTrackedKeywordsToStoreListings < ActiveRecord::Migration[8.0]
  def change
    add_column :store_listings, :tracked_keywords, :jsonb, default: []
  end
end
