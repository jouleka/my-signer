class DropTrackedKeywordsFromStoreListings < ActiveRecord::Migration[8.0]
  # Phase C cleanup: the legacy CSV-ish jsonb column on `store_listings` was
  # the source-of-truth for per-listing tracked keywords before the
  # TrackedKeyword + TrackedKeywordCountry tables existed. `aso:backfill_tracked_keywords`
  # copied all rows into the new tables; after Phase 1-5 shipped and the
  # backfill ran cleanly in production, nothing reads this column anymore.

  def up
    abort_if_backfill_missing!
    remove_column :store_listings, :tracked_keywords, :jsonb, default: []
  end

  # Data it held is gone for good; schema-only reversal is provided for
  # fresh-environment rollback.
  def down
    add_column :store_listings, :tracked_keywords, :jsonb, default: []
  end

  private

  # Refuse to drop the legacy column while it still holds user data that
  # hasn't been copied into TrackedKeyword/TrackedKeywordCountry. This
  # catches the "operator forgot to run aso:backfill_tracked_keywords"
  # foot-gun. Fresh environments (no legacy data) and environments where
  # the rake task already ran to completion both pass through cleanly.
  def abort_if_backfill_missing!
    return unless connection.column_exists?(:store_listings, :tracked_keywords)

    legacy_rows = connection.select_value(<<~SQL).to_i
      SELECT COUNT(*) FROM store_listings
      WHERE tracked_keywords IS NOT NULL
        AND tracked_keywords <> '[]'::jsonb
    SQL

    return if legacy_rows.zero?

    tracked_kw_rows = connection.select_value("SELECT COUNT(*) FROM tracked_keywords").to_i
    return if tracked_kw_rows.positive?

    raise ActiveRecord::IrreversibleMigration, <<~MSG
      Refusing to drop store_listings.tracked_keywords: #{legacy_rows} listing(s)
      still hold legacy jsonb data and TrackedKeyword is empty — the
      aso:backfill_tracked_keywords rake task has not been run.

      Run it before re-running db:migrate:

        bundle exec rake aso:backfill_tracked_keywords DRY_RUN=1
        bundle exec rake aso:backfill_tracked_keywords

      See lib/tasks/aso.rake for the full deploy sequence.
    MSG
  end
end
