class CreateTrackedKeywords < ActiveRecord::Migration[8.0]
  def change
    create_table :tracked_keywords do |t|
      t.references :apple_app, null: false, foreign_key: true, index: true
      t.string :keyword, null: false, limit: 100
      t.integer :search_popularity
      t.datetime :search_popularity_updated_at
      t.string :search_popularity_source, default: "apple_ads_recommendations", null: false
      t.boolean :enabled, default: true, null: false
      t.timestamps
    end
    add_index :tracked_keywords, [ :apple_app_id, :keyword ], unique: true
  end
end
