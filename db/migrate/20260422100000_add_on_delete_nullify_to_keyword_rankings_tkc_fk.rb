class AddOnDeleteNullifyToKeywordRankingsTkcFk < ActiveRecord::Migration[8.0]
  # KeywordRanking#belongs_to :tracked_keyword_country has `dependent: :nullify`
  # (via the has_many on TrackedKeywordCountry); the original
  # AddTrackedKeywordCountryIdToKeywordRankings migration created the FK with
  # Rails's default (NO ACTION), so the model-level nullify works but any raw
  # SQL cascade, partial reads during a cascade delete, or TRUNCATE ... CASCADE
  # would RESTRICT with a FK violation. Align the DB-level FK with the app
  # intent so the two can't drift.
  #
  # The swap is a constraint drop + re-add; PostgreSQL holds an ACCESS
  # EXCLUSIVE on keyword_rankings for the duration. Both steps are O(1) — no
  # row rewrite — so the lock window is milliseconds on production.

  def up
    remove_foreign_key :keyword_rankings, :tracked_keyword_countries, if_exists: true
    add_foreign_key    :keyword_rankings, :tracked_keyword_countries, on_delete: :nullify
  end

  def down
    remove_foreign_key :keyword_rankings, :tracked_keyword_countries, if_exists: true
    add_foreign_key    :keyword_rankings, :tracked_keyword_countries
  end
end
