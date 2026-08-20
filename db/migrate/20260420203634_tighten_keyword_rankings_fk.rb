class TightenKeywordRankingsFk < ActiveRecord::Migration[8.0]
  # Phase C final step for the keyword rank tracker migration
  # (Tasks 20-23). After backfilling `tracked_keyword_country_id` via
  # `aso:backfill_keyword_rankings_fk` and letting the canary ride, this
  # migration drops the legacy polymorphic columns (`listable_type`,
  # `listable_id`, `locale`) that the new schema no longer reads, and
  # swaps the old composite uniqueness index for one keyed on the new FK.
  #
  # NOTE: the `tracked_keyword_country_id` FK is intentionally left NULLABLE.
  # TrackedKeywordCountry#destroy nullifies the FK on its rankings (not
  # delete_all) so users' paid-for rank history survives untracking a
  # keyword — the Retention job eventually cleans rows up by `checked_on`.
  #
  # Prerequisites:
  #   - `aso:backfill_tracked_keywords` has been run (migrates legacy CSV into
  #     TrackedKeyword + TrackedKeywordCountry).
  #   - `aso:backfill_keyword_rankings_fk` has been run (resolves the FK on
  #     existing rows).
  #
  # Deploy safety:
  #   `disable_ddl_transaction!` is required so `CREATE INDEX CONCURRENTLY`
  #   can run without an outer transaction. Each statement below commits
  #   independently; all are idempotent (`if_exists:` / `if_not_exists:`) so
  #   a partial failure can be safely retried by re-running this migration.
  disable_ddl_transaction!

  def up
    abort_if_backfill_missing!

    # Legacy indexes come off individually. Each ALTER takes a brief
    # ACCESS EXCLUSIVE, but without an outer transaction the lock is
    # released immediately — no accumulation across statements.
    remove_index :keyword_rankings, name: "idx_kw_rankings_unique", if_exists: true
    remove_index :keyword_rankings, name: "idx_on_listable_type_listable_id_checked_on_45f690a876", if_exists: true
    remove_index :keyword_rankings, name: "index_keyword_rankings_on_listable", if_exists: true

    remove_column :keyword_rankings, :listable_type, if_exists: true
    remove_column :keyword_rankings, :listable_id,   if_exists: true
    remove_column :keyword_rankings, :locale,        if_exists: true

    # A prior CONCURRENTLY build that failed mid-flight leaves an INVALID
    # index behind with the same name. `if_not_exists: true` on the add
    # below would see the name and skip, leaving a non-enforcing index in
    # place. Drop any invalid leftover first so the retry actually rebuilds.
    has_invalid_leftover = select_value(<<~SQL).present?
      SELECT 1 FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      WHERE c.relname = 'idx_kw_rankings_tkc_checked_on_unique'
        AND NOT i.indisvalid
      LIMIT 1
    SQL
    if has_invalid_leftover
      remove_index :keyword_rankings,
                   name: "idx_kw_rankings_tkc_checked_on_unique",
                   if_exists: true
    end

    # Partial unique index built concurrently — does NOT block concurrent
    # INSERTs or UPDATEs on keyword_rankings, only blocks other schema
    # changes on the same table. `WHERE tracked_keyword_country_id IS NOT
    # NULL` is required because the FK is nullable: rows whose TKC was
    # destroyed (FK nullified by :nullify) carry no uniqueness obligation.
    add_index :keyword_rankings,
              [ :tracked_keyword_country_id, :checked_on ],
              unique: true,
              where: "tracked_keyword_country_id IS NOT NULL",
              name: "idx_kw_rankings_tkc_checked_on_unique",
              algorithm: :concurrently,
              if_not_exists: true
  end

  # WARNING: `down` is structurally reversible but NOT data-safe. Re-adding
  # `listable_type/listable_id/locale` with defaults will backfill every
  # surviving row with sentinel values ("" / 0), silently corrupting the
  # polymorphic association. Rollback is intended for fresh environments
  # or a disaster-recovery restore, not for a live rollback on production.
  def down
    remove_index :keyword_rankings,
                 name: "idx_kw_rankings_tkc_checked_on_unique",
                 algorithm: :concurrently,
                 if_exists: true

    add_column :keyword_rankings, :locale,        :string, null: false, default: "" unless column_exists?(:keyword_rankings, :locale)
    add_column :keyword_rankings, :listable_id,   :bigint, null: false, default: 0  unless column_exists?(:keyword_rankings, :listable_id)
    add_column :keyword_rankings, :listable_type, :string, null: false, default: "" unless column_exists?(:keyword_rankings, :listable_type)

    add_index :keyword_rankings, %i[listable_type listable_id],
              name: "index_keyword_rankings_on_listable",
              algorithm: :concurrently, if_not_exists: true
    add_index :keyword_rankings, %i[listable_type listable_id checked_on],
              name: "idx_on_listable_type_listable_id_checked_on_45f690a876",
              algorithm: :concurrently, if_not_exists: true
    add_index :keyword_rankings, %i[listable_type listable_id keyword locale checked_on],
              unique: true, name: "idx_kw_rankings_unique",
              algorithm: :concurrently, if_not_exists: true
  end

  private

  # Refuse to drop listable_type/listable_id/locale while live rows still
  # depend on them for their app linkage (tracked_keyword_country_id IS
  # NULL). Running this migration before aso:backfill_keyword_rankings_fk
  # would orphan every rank history row. Fresh environments (zero rows)
  # and environments where the rake task already completed both pass
  # through cleanly.
  def abort_if_backfill_missing!
    return unless connection.column_exists?(:keyword_rankings, :listable_id)

    total_rows = connection.select_value("SELECT COUNT(*) FROM keyword_rankings").to_i
    return if total_rows.zero?

    backfilled_rows = connection.select_value(<<~SQL).to_i
      SELECT COUNT(*) FROM keyword_rankings
      WHERE tracked_keyword_country_id IS NOT NULL
    SQL

    return if backfilled_rows.positive?

    raise ActiveRecord::IrreversibleMigration, <<~MSG
      Refusing to drop keyword_rankings.listable_type/listable_id/locale:
      #{total_rows} row(s) exist but none have tracked_keyword_country_id set —
      the aso:backfill_keyword_rankings_fk rake task has not been run.

      Run it before re-running db:migrate:

        bundle exec rake aso:backfill_keyword_rankings_fk DRY_RUN=1
        bundle exec rake aso:backfill_keyword_rankings_fk

      See lib/tasks/aso.rake for the full deploy sequence.
    MSG
  end
end
