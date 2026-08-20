class AddReviewTrackingToReleaseNotes < ActiveRecord::Migration[8.0]
  def change
    change_table :release_notes do |t|
      t.datetime :submitted_for_review_at
      t.references :reviewed_by, foreign_key: { to_table: :users }, null: true
      t.datetime :reviewed_at
      t.text :review_comment
    end

    add_index :release_notes, :submitted_for_review_at
  end
end
