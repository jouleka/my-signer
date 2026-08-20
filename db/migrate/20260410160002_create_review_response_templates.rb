class CreateReviewResponseTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :review_response_templates do |t|
      t.references :organization, null: false, foreign_key: true
      t.string  :name,     null: false
      t.string  :category, default: "general"
      t.text    :body,     null: false
      t.integer :position, default: 0

      t.timestamps
    end

    add_index :review_response_templates, %i[organization_id category]
  end
end
