class CreateAppleAdsRecommendations < ActiveRecord::Migration[8.0]
  def change
    create_table :apple_ads_recommendations do |t|
      t.references :apple_app, null: false, foreign_key: true, index: true
      t.string :keyword, null: false, limit: 100
      t.integer :search_popularity, null: false
      t.datetime :search_popularity_updated_at, null: false
      t.bigint :bid_amount_micros
      t.timestamps
    end
    add_index :apple_ads_recommendations, [ :apple_app_id, :keyword ], unique: true
    add_index :apple_ads_recommendations, [ :apple_app_id, :search_popularity ], order: { search_popularity: :desc }, name: "idx_recs_by_popularity"
  end
end
