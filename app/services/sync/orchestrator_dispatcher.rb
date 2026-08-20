module Sync
  # Fans out a full-org sync by enqueueing every relevant sync job, subject to
  # (a) credential availability and (b) entitlement gates. Each enqueue is
  # independent; the orchestrator never fails the whole batch if one sub-sync
  # can't run.
  #
  # Returns a Hash mapping the sub-job key to its enqueue result:
  #   { asc: :enqueued, google_play: :fresh, reviews: :enqueued, ... }
  #
  # Standalone jobs (reviews/analytics/cpp/keywords) return :enqueued
  # unconditionally when the entitlement is present. Their own advisory locks
  # + entitlement guards handle idempotency and plan downgrades.
  class OrchestratorDispatcher
    include AutoSync # enqueue_app_store_connect_sync / enqueue_google_play_sync

    def initialize(organization:, force: false)
      @organization = organization
      @force = force
    end

    def call
      dispatched = {}

      asc_result = enqueue_platform_sync(:asc)
      if asc_result
        dispatched[:asc] = asc_result
        seed_sync_run(:asc) if asc_result == :enqueued
      end

      gp_result = enqueue_platform_sync(:gp)
      if gp_result
        dispatched[:google_play] = gp_result
        seed_sync_run(:google_play) if gp_result == :enqueued
      end

      entitlements = @organization.entitlements

      if entitlements.review_monitoring_enabled? && !OrgSyncRun.running?(organization_id: @organization.id, job_name: :reviews)
        seed_sync_run(:reviews)
        ReviewSyncJob.perform_later(organization_id: @organization.id)
        dispatched[:reviews] = :enqueued
      end

      if entitlements.analytics_dashboard_enabled? && !OrgSyncRun.running?(organization_id: @organization.id, job_name: :analytics)
        seed_sync_run(:analytics)
        AnalyticsSyncJob.perform_later(organization_id: @organization.id)
        dispatched[:analytics] = :enqueued
      end

      if entitlements.custom_product_pages_enabled? && !OrgSyncRun.running?(organization_id: @organization.id, job_name: :cpp)
        seed_sync_run(:cpp)
        CppSyncJob.perform_later(organization_id: @organization.id)
        dispatched[:cpp] = :enqueued
      end

      if entitlements.keyword_tracking_enabled? && !OrgSyncRun.running?(organization_id: @organization.id, job_name: :keywords_rank)
        seed_sync_run(:keywords_rank)
        Aso::KeywordRankCheckJob.perform_later(organization_id: @organization.id)
        dispatched[:keywords_rank] = :enqueued
      end

      dispatched
    end

    private

    # Create (or refresh) the OrgSyncRun row to status=running *before* the worker
    # picks up the job. This closes the race window where a poll between dispatch
    # and worker-start would see `running: false` and prematurely dismiss the
    # sync-in-progress banner. Safe to call even when the worker will re-call
    # record_started! later — it upserts.
    def seed_sync_run(job_name)
      OrgSyncRun.record_started!(organization: @organization, job_name: job_name)
    rescue StandardError => e
      Rails.logger.warn("OrchestratorDispatcher: failed to seed OrgSyncRun for #{job_name}: #{e.message}")
    end

    def enqueue_platform_sync(platform)
      credential = sync_credential_for_platform(@organization, platform)
      return nil unless credential

      case platform
      when :asc
        enqueue_app_store_connect_sync(
          @organization,
          force: @force,
          min_interval: AutoSync::SYNC_MANUAL_MIN_INTERVAL
        )
      when :gp
        enqueue_google_play_sync(
          @organization,
          force: @force,
          min_interval: AutoSync::SYNC_MANUAL_MIN_INTERVAL
        )
      end
    end
  end
end
