require "concurrent"

class CredentialVault
  # Process-local, thread-safe TTL+LRU cache for *plaintext* DEKs.
  #
  # SECURITY (mysigner H-1 / M-2): plaintext data-encryption keys MUST NOT be
  # written to any out-of-process store. The previous implementation cached
  # unwrapped DEKs in `Rails.cache`, which in production is Solid Cache — an
  # *unencrypted Postgres table*. That put plaintext key material on disk in
  # the clear, defeating the whole point of envelope encryption. This cache
  # keeps DEKs in RAM only; they never leave the process and die with it.
  #
  # The cache is intentionally tiny and dependency-light:
  #   * `Concurrent::Map` for lock-free reads/writes of the entry table.
  #   * Per-entry monotonic-clock expiry (TTL). Reads of an expired entry treat
  #     it as a miss and evict it.
  #   * A soft LRU bound (`MAX_ENTRIES`) so a long-lived process that touches
  #     many credentials can't grow the table without limit. When the bound is
  #     exceeded we evict the oldest-inserted entries (approximate LRU — good
  #     enough for a key cache; correctness never depends on a hit).
  #
  # All operations are fail-safe: a cache miss simply re-derives the DEK via
  # KMS, so eviction/expiry can never cause a wrong decrypt.
  class DekCache
    # Default TTL for env-default-CMK DEKs. Matches the prior Rails.cache
    # `expires_in: 1.hour` behavior so per-credential KMS call volume is
    # unchanged for the common case.
    DEFAULT_TTL = 3600 # seconds (1 hour)

    # Much shorter TTL for BYOK (customer-managed CMK) DEKs so that a customer
    # revoking their CMK becomes fail-closed quickly: once the cached DEK
    # expires (<=2 min) the next decrypt goes back to KMS and surfaces the
    # revocation as CustomerKeyRevoked. A long TTL would let us keep serving
    # plaintext for up to an hour after the customer pulled access (M-2).
    BYOK_TTL = 90 # seconds

    # Soft upper bound on cached entries. Each entry is one ~32-byte DEK plus
    # bookkeeping; this bound exists to cap unbounded growth, not for memory
    # pressure. Evicts oldest-inserted on overflow.
    MAX_ENTRIES = 2048

    Entry = Struct.new(:value, :expires_at, :inserted_at)

    class << self
      def instance
        @instance ||= new
      end

      # Delegate the common operations to the process-wide singleton so callers
      # can use `CredentialVault::DekCache.fetch(...)` without threading an
      # instance around.
      def fetch(key, ttl:, &block)
        instance.fetch(key, ttl: ttl, &block)
      end

      def delete(key)
        instance.delete(key)
      end

      def clear
        instance.clear
      end
    end

    def initialize
      @store = Concurrent::Map.new
      # Guards only the LRU trim/eviction bookkeeping, which must read the whole
      # table consistently. The hot read/write path uses Concurrent::Map
      # directly and does not take this lock.
      @trim_mutex = Mutex.new
    end

    # Return the cached plaintext DEK for +key+, or compute it via the block,
    # store it with the given +ttl+ (seconds), and return it. Expired entries
    # are treated as misses. The block is expected to perform the KMS unwrap.
    #
    # A ttl of 0 (or negative) bypasses caching entirely: the block runs and
    # its result is returned without ever being stored (used for a hard
    # fail-closed BYOK mode if desired).
    def fetch(key, ttl:)
      now = monotonic_now

      existing = @store[key]
      return existing.value if existing && existing.expires_at > now

      value = yield
      store(key, value, ttl, now) if ttl.to_f > 0
      value
    end

    # Evict a single entry by key. Used by OrgRewrap (L-1) to drop the cached
    # plaintext DEK for an OLD wrapped_dek the moment its envelope is rotated
    # away, so a rotated-out key doesn't linger in RAM until TTL.
    def delete(key)
      @store.delete(key)
      nil
    end

    # Drop every cached DEK. Not used in the hot path; handy for tests and an
    # in-process incident response alongside the MYSIGNER_DEK_CACHE_VERSION bump.
    def clear
      @store.clear
      nil
    end

    private

    def store(key, value, ttl, now)
      @store[key] = Entry.new(value, now + ttl.to_f, now)
      trim_if_needed
      value
    end

    # Approximate LRU: when over the soft bound, drop the oldest-inserted
    # entries. Guarded so concurrent stores don't double-trim. Correctness is
    # unaffected by over- or under-eviction (misses just re-derive via KMS).
    def trim_if_needed
      return if @store.size <= MAX_ENTRIES

      @trim_mutex.synchronize do
        size = @store.size
        return if size <= MAX_ENTRIES

        # Snapshot key/inserted_at pairs, sort oldest-first, evict the overflow.
        pairs = []
        @store.each_pair { |k, entry| pairs << [ k, entry.inserted_at ] }
        pairs.sort_by! { |(_k, inserted_at)| inserted_at }

        (size - MAX_ENTRIES).times do |i|
          key = pairs[i]&.first
          @store.delete(key) if key
        end
      end
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
