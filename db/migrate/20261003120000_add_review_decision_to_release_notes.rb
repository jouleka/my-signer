class AddReviewDecisionToReleaseNotes < ActiveRecord::Migration[8.0]
  def up
    add_column :release_notes, :review_decision, :string
    # Before this column existed, approve_review! accepted an optional comment
    # and reject_review! required one, and both returned the note to "draft".
    # A review comment therefore does NOT unambiguously mean rejection, and the
    # old app never blocked a push on a commented review (only pending_review
    # blocked). To avoid suddenly deadlocking historical notes, every
    # completed legacy review is backfilled as approved. Notes still awaiting
    # review (reviewed_at IS NULL) are untouched and keep requiring review.
    execute <<~SQL
      UPDATE release_notes
      SET review_decision = 'approved'
      WHERE reviewed_at IS NOT NULL AND review_decision IS NULL
    SQL
  end

  def down
    remove_column :release_notes, :review_decision
  end
end
