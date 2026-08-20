module Sync
  # Composes a single payload describing the state of a sync_all run,
  # suitable for the `sync_controller.js` Stimulus controller to consume
  # unchanged. Top-level keys mirror the per-platform status endpoints:
  #
  #   { running: Boolean,
  #     last_synced_at: Time | nil,
  #     last_sync_status: "ok" | "partial" | "error" | "running",
  #     last_sync_error: String | nil,
  #     jobs: { "asc" => {...}, "reviews" => {...}, ... } }
  #
  # Liveness detection. An OrgSyncRun can be stranded at status="running"
  # if the worker process dies between `record_started!` and
  # `record_finished!` (dev reload, SIGKILL during deploy, OOM, host
  # reboot). Every sync job except keywords_popularity guards its body
  # with a session-level `pg_try_advisory_lock` — the lock is held only
  # as long as the owning DB session is alive, so a dead worker
  # releases it automatically. We use that as the definitive signal:
  #
  #   status=running AND lock held   → live
  #   status=running AND lock absent → stranded (surfaced as error)
  #
  # Two caveats on top of the base rule:
  #   1. WORKER_PICKUP_GRACE — there's a tiny window between
  #      orchestrator-seeded `record_started!` and the worker actually
  #      taking its `pg_try_advisory_lock`. Treat runs younger than this
  #      as live regardless of lock state.
  #   2. keywords_popularity (and any future jobs without an advisory
  #      lock) fall back to the time-based STALE_RUN_THRESHOLD.
  #
  # SyncRunReaperJob still runs periodically to flip stranded rows to
  # status=error on the DB side so history is coherent.
  class StatusAggregator
    STALE_RUN_THRESHOLD   = 15.minutes
    WORKER_PICKUP_GRACE   = 30.seconds
    STALE_ERROR_MESSAGE   = "Sync did not complete (worker exited before finishing)".freeze

    # Maps OrgSyncRun#job_name → the advisory lock key the corresponding
    # job takes in its `with_advisory_lock(...)` guard. Keep in lockstep
    # with the job files under app/jobs/ — the aggregator's liveness
    # check is wrong if this drifts.
    def self.advisory_lock_key_for(job_name, organization_id)
      case job_name.to_s
      when "asc"           then "asc:sync:org:#{organization_id}"
      when "google_play"   then "gp:sync:org:#{organization_id}"
      when "cpp"           then "cpp:sync:org:#{organization_id}"
      when "analytics"     then "analytics:sync:org:#{organization_id}"
      when "reviews"       then "reviews:sync:org:#{organization_id}"
      when "keywords_rank" then "keywords:sync:org:#{organization_id}"
      end
    end

    def initialize(organization:)
      @organization = organization
    end

    def payload
      # Query directly to bypass any stale has_many cache on the passed-in
      # organization (callers that seeded rows in the same request expect
      # the aggregator to see them immediately).
      runs = OrgSyncRun.for_org(@organization).to_a
      return empty_payload if runs.empty?

      @held_advisory_lock_ids = fetch_held_advisory_lock_ids(runs)

      {
        running: runs.any? { |r| live_running?(r) },
        last_synced_at: runs.filter_map(&:finished_at).max,
        last_sync_status: compose_status(runs),
        last_sync_error: first_error_message(runs),
        jobs: runs.index_by(&:job_name).transform_values { |r| serialize(r) }
      }
    end

    private

    # A run is "live running" if we have positive evidence its worker is
    # still alive. Evidence, in order of preference:
    #   1. The row was written within WORKER_PICKUP_GRACE (too fresh to
    #      distinguish "not picked up yet" from "dead"). Trust it.
    #   2. We know this job's advisory-lock key and that lock is held in
    #      pg_locks. Definitive.
    #   3. We don't know the lock key — fall back to STALE_RUN_THRESHOLD.
    def live_running?(run)
      return false unless run.status == "running"
      return true if fresh_grace?(run)

      lock_id = advisory_lock_id_for(run)
      if lock_id && @held_advisory_lock_ids
        return @held_advisory_lock_ids.include?(lock_id)
      end

      !time_stale?(run)
    end

    def fresh_grace?(run)
      run.started_at.present? && run.started_at > WORKER_PICKUP_GRACE.ago
    end

    def time_stale?(run)
      run.started_at.present? && run.started_at < STALE_RUN_THRESHOLD.ago
    end

    # Distinct from `!live_running?` in that it's specifically "claimed
    # running but actually stranded" — used to pick the per-row
    # effective status and error message.
    def stranded?(run)
      run.status == "running" && !live_running?(run)
    end

    def effective_status(run)
      stranded?(run) ? "error" : run.status
    end

    def advisory_lock_id_for(run)
      key = self.class.advisory_lock_key_for(run.job_name, run.organization_id)
      return nil unless key
      Zlib.crc32(key)
    end

    # Single pg_locks probe per payload. Returns a Set of objid ints that
    # still have a LIVE holder. On probe failure returns nil — callers
    # interpret that as "unknown, fall back to the time threshold" so a
    # transient DB blip can't mass-flag every run as dead.
    #
    # NOTE on the JOIN: `pg_locks` can keep a stale row pointing at a PID
    # that no longer exists in `pg_stat_activity` for up to TCP-keepalive
    # seconds after the client died (empirically observed on dev macOS;
    # default postgres tcp_keepalives_idle is several minutes). Joining
    # against pg_stat_activity is the fast signal — the activity row
    # disappears the instant the backend exits, so a dead worker's lock
    # is correctly excluded from this set immediately.
    #
    # NOTE on uncached: ActiveRecord's per-request QueryCache would happily
    # memoize this result, but the point of the probe is to reflect the
    # current live state of pg_stat_activity. Skip the cache defensively
    # so a future caller who invokes the aggregator twice in one request
    # (or inside a long-running job) still gets accurate data.
    def fetch_held_advisory_lock_ids(runs)
      lock_ids = runs
                   .select { |r| r.status == "running" }
                   .filter_map { |r| advisory_lock_id_for(r) }
                   .uniq
      return Set.new if lock_ids.empty?

      sql = ActiveRecord::Base.sanitize_sql_array([
        <<~SQL.squish, lock_ids
          SELECT DISTINCT l.objid
          FROM pg_locks l
          INNER JOIN pg_stat_activity a ON a.pid = l.pid
          WHERE l.locktype = 'advisory'
            AND l.objid IN (?)
        SQL
      ])

      values = ActiveRecord::Base.connection.uncached do
        ActiveRecord::Base.connection.select_values(sql)
      end
      Set.new(values.map(&:to_i))
    rescue StandardError => e
      Rails.logger.warn("Sync::StatusAggregator pg_locks probe failed: #{e.class}: #{e.message}")
      nil
    end

    def empty_payload
      { running: false, last_synced_at: nil, last_sync_status: "ok", last_sync_error: nil, jobs: {} }
    end

    def compose_status(runs)
      return "running" if runs.any? { |r| live_running?(r) }

      terminal = runs.reject { |r| live_running?(r) }
      return "ok" if terminal.empty?

      statuses = terminal.map { |r| effective_status(r) }.uniq
      if statuses == [ "ok" ]
        "ok"
      elsif statuses == [ "error" ]
        "error"
      else
        "partial"
      end
    end

    def first_error_message(runs)
      stranded = runs.find { |r| stranded?(r) }
      return STALE_ERROR_MESSAGE if stranded

      runs.find { |r| r.status == "error" }&.error_message
    end

    def serialize(run)
      {
        status: effective_status(run),
        started_at: run.started_at,
        finished_at: run.finished_at,
        error_message: stranded?(run) ? STALE_ERROR_MESSAGE : run.error_message
      }
    end
  end
end
