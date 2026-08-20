class CreateTrackedKeywordCountries < ActiveRecord::Migration[8.0]
  def change
    create_table :tracked_keyword_countries do |t|
      t.references :tracked_keyword, null: false, foreign_key: true
      t.string :country, null: false, limit: 2
      t.datetime :last_checked_at
      t.integer :current_rank
      t.integer :previous_rank
      t.integer :competition_count
      t.boolean :enabled, default: true, null: false
      t.timestamps
    end
    add_index :tracked_keyword_countries, [ :tracked_keyword_id, :country ], unique: true
    add_index :tracked_keyword_countries, [ :country, :last_checked_at ]
  end
end
