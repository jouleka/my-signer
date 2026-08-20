class CreateKeywordRankings < ActiveRecord::Migration[8.0]
  def change
    create_table :keyword_rankings do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :listable, polymorphic: true, null: false
      t.string :keyword, null: false
      t.string :locale, null: false
      t.integer :rank  # nil = not ranked in top 200
      t.date :checked_on, null: false
      t.timestamps
    end
    add_index :keyword_rankings, [ :listable_type, :listable_id, :keyword, :locale, :checked_on ],
              unique: true, name: "idx_kw_rankings_unique"
    add_index :keyword_rankings, [ :listable_type, :listable_id, :checked_on ]
  end
end
