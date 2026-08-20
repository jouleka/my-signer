class AddCompositeIndexToKeywordRankings < ActiveRecord::Migration[8.0]
  # Aso::KeywordHistoryRetentionJob filters on (organization_id, checked_on)
  # every Sunday 3am UTC, one pass per Organization. After Phase C only
  # `organization_id` is indexed in isolation, so the planner scans every
  # org-scoped partition then filters by checked_on — fine for small orgs,
  # slow for Team-tier orgs with months of history. A composite index on
  # (organization_id, checked_on) lets the planner satisfy both predicates
  # with a single range scan.
  #
  # CONCURRENTLY so the weekly build never blocks the nightly rank-check
  # writers. disable_ddl_transaction! is required by CONCURRENTLY.
  disable_ddl_transaction!

  def change
    add_index :keyword_rankings,
              [ :organization_id, :checked_on ],
              name: "idx_keyword_rankings_on_org_and_checked_on",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
