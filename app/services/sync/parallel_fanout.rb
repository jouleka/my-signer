require "concurrent"

module Sync
  # Runs a block for each item in parallel on a bounded thread pool.
  #
  # Each thread checks out its own ActiveRecord connection (required when
  # the worker threads do any DB work) and releases it when the future
  # resolves. Errors inside one future do not abort the others — the block
  # is expected to handle its own per-item rescue if partial failure should
  # be tolerated, otherwise `call` re-raises the first error after draining
  # the rest.
  #
  # Concurrency is capped by `max_threads` (default 6) which roughly
  # matches our Solid Queue thread budget and stays well under typical DB
  # connection-pool sizes. Bump via the `SYNC_FANOUT_THREADS` env var for
  # tuning without a code change.
  module ParallelFanout
    DEFAULT_MAX_THREADS = (ENV["SYNC_FANOUT_THREADS"] || 6).to_i

    module_function

    def call(items, max_threads: DEFAULT_MAX_THREADS)
      items = items.to_a
      return [] if items.empty?
      return [ yield(items.first) ] if items.size == 1

      pool = Concurrent::FixedThreadPool.new([ items.size, max_threads ].min)
      begin
        futures = items.map do |item|
          Concurrent::Promises.future_on(pool) do
            ActiveRecord::Base.connection_pool.with_connection do
              yield(item)
            end
          end
        end
        Concurrent::Promises.zip(*futures).value!
      ensure
        pool.shutdown
        pool.wait_for_termination(60)
      end
    end
  end
end
