class SyncRunReaperJob < ApplicationJob
  queue_as :default

  # Marks `OrgSyncRun` rows stuck at status=running as error. A sync row
  # strands when the worker process dies between record_started! and
  # record_finished! (hard SIGKILL during deploy, OOM, host reboot, crash
  # inside a C extension, etc) because ensure blocks never run on a hard
  # kill. Sync::StatusAggregator already hides these from the UI after
  # STALE_RUN_THRESHOLD via an in-query staleness check, so this job is
  # DB hygiene — it gives us a real terminal row to audit in the table
  # instead of a permanent "running" relic.
  #
  # Kept in lockstep with the aggregator's threshold: a row the UI already
  # treats as abandoned is immediately eligible for reaping.
  STALE_AFTER = ::Sync::StatusAggregator::STALE_RUN_THRESHOLD
  REAPER_ERROR_MESSAGE = "Reaper: sync abandoned before completion (worker process ended)".freeze

  def perform
    cutoff = STALE_AFTER.ago
    count = OrgSyncRun
              .where(status: "running")
              .where("started_at < ?", cutoff)
              .update_all(
                status: "error",
                finished_at: Time.current,
                error_message: REAPER_ERROR_MESSAGE,
                updated_at: Time.current
              )
    Rails.logger.info("[SyncRunReaper] Reaped #{count} abandoned sync runs (started_at < #{cutoff.iso8601})") if count && count > 0
    count
  end
end
