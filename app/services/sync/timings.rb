module Sync
  # Lightweight timing instrumentation for the sync pipeline.
  #
  # Emits a single structured log line per phase, tagged with [SyncTimings]
  # so you can `grep -E '\[SyncTimings\]'` a sync run and get a flat timeline
  # of every external-API block, per-app loop, and per-phase cost.
  #
  # Usage:
  #   Sync::Timings.measure("asc.bundle_ids", org_id: org.id) do
  #     # ... work ...
  #   end
  #
  # Output:
  #   [SyncTimings] phase=asc.bundle_ids org=42 ms=234
  #
  # Labels can be freely composed (`"#{phase}.#{sub}"`). Keep them stable so
  # the log can be aggregated mechanically.
  module Timings
    module_function

    def measure(phase, **tags)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      emit(phase, started, **tags, ok: true)
      result
    rescue StandardError => e
      emit(phase, started, **tags, ok: false, error: e.class.name)
      raise
    end

    def emit(phase, started, **tags)
      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      parts = [ "[SyncTimings]", "phase=#{phase}", "ms=#{ms}" ]
      tags.each { |k, v| parts << "#{k}=#{v}" }
      Rails.logger.info(parts.join(" "))
    end
  end
end
