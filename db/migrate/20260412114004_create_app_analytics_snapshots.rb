class CreateAppAnalyticsSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :app_analytics_snapshots do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :snapshotable_type, null: false
      t.bigint :snapshotable_id, null: false
      t.date :snapshot_date, null: false

      # Acquisition metrics
      t.integer :first_time_downloads, default: 0
      t.integer :redownloads, default: 0
      t.integer :total_downloads, default: 0
      t.integer :impressions, default: 0
      t.integer :product_page_views, default: 0
      t.integer :updates, default: 0
      t.decimal :conversion_rate, precision: 5, scale: 2

      # App usage / quality metrics
      t.integer :sessions, default: 0
      t.integer :active_devices, default: 0
      t.integer :crashes, default: 0
      t.decimal :crash_rate, precision: 8, scale: 6
      t.decimal :anr_rate, precision: 8, scale: 6

      # Source metadata
      t.string :data_source

      t.timestamps
    end

    add_index :app_analytics_snapshots,
      [ :snapshotable_type, :snapshotable_id, :snapshot_date ],
      unique: true,
      name: "idx_analytics_snapshots_app_date"

    add_index :app_analytics_snapshots, [ :organization_id, :snapshot_date ]
  end
end
