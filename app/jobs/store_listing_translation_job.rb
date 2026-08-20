class StoreListingTranslationJob < ApplicationJob
  queue_as :default

  # Translates a store listing from a base listing using OpenAI.
  #
  # @param organization_id [Integer]
  # @param store_listing_id [Integer] Target listing to translate into
  # @param base_listing_id [Integer] Source listing to translate from
  # @param fields [String] "all" or comma-separated field names
  def perform(organization_id:, store_listing_id:, base_listing_id:, fields: "all")
    organization = Organization.find_by(id: organization_id)
    return unless organization

    target_listing = organization.store_listings.find_by(id: store_listing_id)
    return unless target_listing

    base_listing = organization.store_listings.find_by(id: base_listing_id)
    return unless base_listing

    # Parse fields
    field_list = fields == "all" ? :all : fields.split(",").map(&:strip).map(&:to_sym)

    # Optimistic decrement: check quota and increment counter under lock,
    # then release lock before making the slow OpenAI API call.
    can_translate = false
    organization.with_lock do
      entitlements = organization.entitlements
      remaining = entitlements.ai_translations_remaining(organization)
      if remaining <= 0
        Rails.logger.warn("StoreListingTranslationJob: Translation limit reached for org #{organization_id}")
      else
        organization.increment!(:ai_translations_count)
        can_translate = true
      end
    end

    return unless can_translate

    # Translate outside the lock — no DB lock held during network I/O
    begin
      StoreListingSync::AiTranslator.new(
        base_listing: base_listing,
        target_listing: target_listing,
        fields: field_list
      ).translate!
      # Push a live refresh so any page subscribed with
      # `turbo_stream_from @store_listing` morphs in place: button returns to
      # idle, translated fields appear below.
      target_listing.trigger_live_refresh
    rescue StandardError => e
      # Rollback the quota consumed for a failed translation
      organization.with_lock do
        organization.reload
        organization.decrement!(:ai_translations_count) if organization.ai_translations_count > 0
      end
      # Unstick the "Translating…" pill on subscribed pages — without this the
      # button is frozen until the user manually reloads. Wrapped in its own
      # rescue so broadcast errors never mask the real failure.
      begin
        target_listing.trigger_live_refresh
      rescue StandardError
        # ignore — primary error is still raised below
      end
      raise
    ensure
      # Release the per-listing translation lock regardless of outcome so the
      # user can re-trigger translation after either success or failure.
      # See ReleasesController#translate.
      Rails.cache.delete("translating_listing_#{target_listing.id}") if target_listing
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn("StoreListingTranslationJob: Record not found - #{e.message}")
  rescue StandardError => e
    Rails.logger.error("StoreListingTranslationJob failed: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
    raise
  end
end
