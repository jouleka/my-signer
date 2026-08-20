class AddPushTrackingToStoreListings < ActiveRecord::Migration[8.0]
  def change
    add_column :store_listings, :push_status, :string
    add_column :store_listings, :push_error, :text
    add_column :store_listings, :push_fields_skipped, :jsonb, default: []
    add_column :store_listings, :last_pushed_at, :datetime
  end
end
