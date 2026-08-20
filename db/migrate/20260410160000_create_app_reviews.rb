class CreateAppReviews < ActiveRecord::Migration[8.0]
  def change
    create_table :app_reviews do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :reviewable, polymorphic: true, null: false

      t.string  :remote_id,     null: false
      t.integer :rating,        null: false
      t.string  :title
      t.text    :body,          null: false
      t.string  :reviewer_name
      t.string  :territory
      t.string  :language
      t.datetime :reviewed_at,  null: false
      t.string  :sentiment,     default: "neutral"

      t.text    :reply_text
      t.datetime :reply_posted_at
      t.string  :reply_status,  default: "none"

      t.jsonb   :raw_json,      default: {}

      t.timestamps
    end

    add_index :app_reviews, %i[reviewable_type reviewable_id remote_id], unique: true, name: "idx_app_reviews_reviewable_remote"
    add_index :app_reviews, %i[organization_id reviewed_at]
    add_index :app_reviews, %i[organization_id sentiment]
  end
end
