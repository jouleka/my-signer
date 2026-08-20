class CreateRatingSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :rating_snapshots do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :snapshotable, polymorphic: true, null: false

      t.date    :snapshot_date,  null: false
      t.decimal :average_rating, precision: 3, scale: 2, null: false
      t.integer :review_count,   default: 0
      t.integer :rating_1_count, default: 0
      t.integer :rating_2_count, default: 0
      t.integer :rating_3_count, default: 0
      t.integer :rating_4_count, default: 0
      t.integer :rating_5_count, default: 0

      t.timestamps
    end

    add_index :rating_snapshots, %i[snapshotable_type snapshotable_id snapshot_date],
              unique: true, name: "idx_rating_snapshots_snapshotable_date"
  end
end
