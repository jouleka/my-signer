module StoreListingSync
  # A sync has its own lifecycle. Existing listing timestamps cannot tell us
  # whether a newly queued import has finished (or failed before writing rows).
  class OperationStatus
    ACTIVE_STATUSES = %w[queued running retrying].freeze
    # A queued/running sync that has not reported progress in this window is
    # treated as dead so it cannot block push or a new sync for the full TTL.
    STALE_AFTER = 15.minutes
    STALE_MESSAGE = "Sync did not finish. Sync again to retry.".freeze

    def initialize(app)
      @key = "store_listing_sync/#{app.organization_id}/#{app.class.name}/#{app.id}"
    end

    def read
      operation = Rails.cache.read(@key) || {}
      return operation unless stale?(operation)

      operation.merge(status: "failed", error: STALE_MESSAGE)
    end

    def start
      operation = { id: SecureRandom.uuid, status: "queued", updated_at: Time.current.to_i }
      Rails.cache.write(@key, operation, expires_in: 1.hour)
      operation
    end

    def update(id, status:, error: nil)
      return unless id && Rails.cache.read(@key)&.dig(:id) == id
      Rails.cache.write(@key, { id: id, status: status, error: error, updated_at: Time.current.to_i }, expires_in: 1.hour)
    end

    def active?
      ACTIVE_STATUSES.include?(read[:status])
    end

    private

    # Entries written before updated_at existed are not considered stale;
    # they expire with the 1-hour TTL as before.
    def stale?(operation)
      ACTIVE_STATUSES.include?(operation[:status]) && operation[:updated_at].present? &&
        Time.zone.at(operation[:updated_at]) < STALE_AFTER.ago
    end
  end
end
