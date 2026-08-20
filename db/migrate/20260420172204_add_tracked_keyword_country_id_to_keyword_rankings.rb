class AddTrackedKeywordCountryIdToKeywordRankings < ActiveRecord::Migration[8.0]
  def change
    add_reference :keyword_rankings, :tracked_keyword_country, foreign_key: true, null: true
    # NOTE: column stays nullable through Phase A (this task) + B (backfill rake).
    # Phase C (Task 23 — separate follow-up PR) flips to NOT NULL and drops the
    # legacy listable_type/listable_id/locale columns.
  end
end
