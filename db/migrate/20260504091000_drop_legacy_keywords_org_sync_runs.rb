class DropLegacyKeywordsOrgSyncRuns < ActiveRecord::Migration[8.0]
  # The keyword sync orchestrator was renamed `keywords` -> `keywords_rank`
  # (the worker tracks itself under the new name; the orchestrator was
  # updated to seed the same name; both `OrgSyncRun::JOB_NAMES` and the
  # advisory-lock map dropped the old `keywords` entry). Existing rows
  # with `job_name = 'keywords'` predate that change.
  #
  # The model validation only fires on save, so legacy rows persist in
  # the DB. They become a permanent eyesore: the aggregator has no
  # advisory-lock key for `keywords` anymore, so the row falls through
  # to STALE_RUN_THRESHOLD and pins to `effective_status = "error"`
  # forever. The orchestrator never re-finishes those rows because
  # `record_finished!(:keywords)` would raise ArgumentError on the
  # dropped name. Without this cleanup, every dashboard with a stranded
  # legacy row goes red on deploy and stays red.
  #
  # Hard delete instead of rename: keeping the row would leave an
  # error-state entry the user can't dismiss (the dismissal controller
  # validates against JOB_NAMES too). The next legitimate sync seeds a
  # fresh `keywords_rank` row.
  def up
    deleted = execute("DELETE FROM org_sync_runs WHERE job_name = 'keywords'").cmd_tuples
    say "Deleted #{deleted} legacy OrgSyncRun row(s) with job_name='keywords'"
  end

  def down
    # Irreversible -- the deleted rows carried no business meaning we
    # could reconstruct, and the new `keywords_rank` rows are the
    # canonical record going forward.
    raise ActiveRecord::IrreversibleMigration
  end
end
