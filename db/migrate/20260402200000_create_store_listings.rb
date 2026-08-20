class CreateStoreListings < ActiveRecord::Migration[8.0]
  def change
    create_table :store_listings do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :listable, polymorphic: true, null: false
      t.string :locale, null: false
      t.string :app_name
      t.string :subtitle
      t.string :keywords
      t.string :short_description
      t.text :description
      t.text :promotional_text
      t.text :whats_new
      t.string :support_url
      t.string :marketing_url
      t.string :privacy_policy_url
      t.jsonb :metadata, default: {}
      t.string :sync_status, default: "draft", null: false
      t.string :translation_status
      t.datetime :last_synced_at
      t.timestamps
    end

    add_index :store_listings, [ :listable_type, :listable_id, :locale ],
              unique: true, name: "idx_store_listings_listable_locale"
    add_index :store_listings, [ :organization_id, :listable_type ],
              name: "idx_store_listings_org_type"
    add_index :store_listings, :sync_status
  end
end
