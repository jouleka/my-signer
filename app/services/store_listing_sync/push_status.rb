module StoreListingSync
  class PushStatus
    def self.for(app)
      listings = app.store_listings.to_a
      # A stale "pushing" listing is a dead push: report it as failed so the
      # UI stops polling and the user can push again.
      states = listings.map { |listing| effective_status(listing) }.compact
      status = if states.include?("pushing")
        "pushing"
      elsif states.include?("failed")
        "failed"
      elsif states.include?("partial_success")
        "partial_success"
      elsif states.present? && states.all? { |state| state == "success" }
        "success"
      end
      {
        push_status: status,
        push_error: listings.select { |listing| effective_status(listing) == "failed" }
          .map { |listing| "#{listing.locale}: #{error_for(listing)}" }.join("; ").presence,
        push_fields_skipped: listings.flat_map { |listing| Array(listing.push_fields_skipped).map { |field| "#{listing.locale}: #{field}" } },
        last_pushed_at: listings.filter_map(&:last_pushed_at).max&.iso8601
      }
    end

    def self.effective_status(listing)
      listing.push_stale? ? "failed" : listing.push_status
    end

    def self.error_for(listing)
      return StoreListing::PUSH_INTERRUPTED_MESSAGE if listing.push_stale?
      listing.push_error.presence || "Push failed"
    end
  end
end
