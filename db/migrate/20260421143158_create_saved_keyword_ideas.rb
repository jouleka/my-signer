class CreateSavedKeywordIdeas < ActiveRecord::Migration[8.0]
  def change
    create_table :saved_keyword_ideas do |t|
      t.references :apple_app, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :keyword, null: false, limit: 100
      t.references :added_by_user, foreign_key: { to_table: :users, on_delete: :nullify }, null: true
      t.timestamps
    end

    add_index :saved_keyword_ideas, [ :apple_app_id, :keyword ], unique: true
  end
end
