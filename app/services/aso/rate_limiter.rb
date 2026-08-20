module Aso
  # Minimum-interval gate for outbound requests to Apple's MZStore.woa
  # endpoint (and any other shared ASO upstream). Apple documents an
  # implicit 15 req/min budget for the suggestions endpoint, which
  # translates to one request every 4 seconds.
  #
  # Backed by Rails.cache so it works with the app's default solid_cache
  # store (DB-backed) — no Redis-specific primitives are used. Every
  # process sharing the cache shares the gate.
  #
  # Returns true when the caller may proceed (after any synchronous
  # sleep) and false when the required wait would exceed MAX_WAIT — at
  # which point the caller should raise {Exhausted} and re-enqueue the
  # job with backoff rather than tying up a Sidekiq worker.
  class RateLimiter
    class Exhausted < StandardError; end

    # 15 req/min = 1 request every 4 seconds
    MIN_INTERVAL = 4.seconds
    # Maximum synchronous wait; beyond this, the caller should reschedule.
    MAX_WAIT = 10.seconds
    KEY = "aso/ratelimit/last_request_at".freeze

    # Returns true if the caller may proceed (after any necessary sleep);
    # false if the required wait would exceed MAX_WAIT — caller should
    # raise Exhausted and re-enqueue the job with backoff.
    def self.acquire
      now = Time.current.to_f
      last = Rails.cache.read(KEY).to_f
      # Clock regression / cached future timestamp must not produce a negative
      # elapsed — that would cascade into a wait_needed larger than MIN_INTERVAL.
      elapsed = [ now - last, 0.0 ].max

      if elapsed >= MIN_INTERVAL
        Rails.cache.write(KEY, now)
        return true
      end

      wait_needed = MIN_INTERVAL - elapsed
      return false if wait_needed > MAX_WAIT

      sleep(wait_needed)
      Rails.cache.write(KEY, Time.current.to_f)
      true
    end
  end
end
