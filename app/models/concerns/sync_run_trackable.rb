# Wrap a job's body with start/finish tracking into `OrgSyncRun`.
# Mix into any ActiveJob subclass that corresponds to a tracked sync.
#
# Usage:
#   class ReviewSyncJob < ApplicationJob
#     include SyncRunTrackable
#
#     def perform(organization_id:)
#       org = Organization.find_by(id: organization_id) or return
#       track_sync_run(organization: org, job_name: :reviews) do
#         # existing body
#       end
#     end
#   end
#
# Terminal-state guarantee: ok + StandardError paths both reach
# record_finished!. An `ensure` clause catches any non-StandardError exit
# (SignalException, SystemExit, Interrupt, or graceful Thread#kill during
# dev-server reload) so the row never strands at status=running when the
# stack actually unwound. Hard SIGKILLs skip Ruby entirely — that case is
# handled by Sync::StatusAggregator's staleness window and
# SyncRunReaperJob's nightly sweep.
module SyncRunTrackable
  extend ActiveSupport::Concern
  include SanitizesCredentialErrors

  ABORTED_ERROR_MESSAGE = "Aborted: worker exited before sync completed".freeze

  private

  def track_sync_run(organization:, job_name:)
    OrgSyncRun.record_started!(organization: organization, job_name: job_name)
    finalized = false
    begin
      result = ::Sync::Timings.measure("job.#{job_name}", org: organization.id) { yield }
      OrgSyncRun.record_finished!(organization: organization, job_name: job_name, status: :ok)
      finalized = true
      result
    rescue StandardError => e
      OrgSyncRun.record_finished!(
        organization: organization,
        job_name: job_name,
        status: :error,
        error_message: sanitize_error(e.message)
      )
      finalized = true
      raise
    ensure
      unless finalized
        # Non-StandardError exit (Exception subclass, signal, graceful
        # thread kill). Ruby still runs this ensure block while unwinding,
        # so we get one last chance to release the row from "running".
        # Swallow any error here — ensure must never raise over another
        # in-flight exception.
        begin
          OrgSyncRun.record_finished!(
            organization: organization,
            job_name: job_name,
            status: :error,
            error_message: ABORTED_ERROR_MESSAGE
          )
        rescue StandardError => inner
          Rails.logger.warn("SyncRunTrackable: ensure-path record_finished! failed for #{job_name}: #{inner.message}")
        end
      end
    end
  end
end
