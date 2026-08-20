class StoreListingPushJob < ApplicationJob
  include SanitizesErrorMessage

  queue_as :default

  # Pushes local StoreListing changes to App Store Connect or Google Play.
  #
  # @param organization_id [Integer]
  # @param store_listing_id [Integer]
  def perform(organization_id:, store_listing_id:)
    organization = Organization.find(organization_id)
    store_listing = organization.store_listings.find(store_listing_id)

    store_listing.update_columns(push_status: "pushing", push_error: nil)

    case store_listing.listable_type
    when "AppleApp"
      StoreListingSync::ApplePusher.new(
        organization: organization,
        store_listing: store_listing
      ).push!
    when "AndroidApp"
      StoreListingSync::GooglePusher.new(
        organization: organization,
        store_listing: store_listing
      ).push!
    else
      raise ArgumentError, "Unsupported listable type: #{store_listing.listable_type}"
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn("StoreListingPushJob: Record not found - #{e.message}")
  rescue StandardError => e
    Rails.logger.error("StoreListingPushJob failed: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace&.first(10)&.join("\n"))

    # Record the error on the listing so the UI can display it
    store_listing = Organization.find_by(id: organization_id)
      &.store_listings&.find_by(id: store_listing_id)
    if store_listing
      error_msg = sanitize_error_message(e)
      store_listing.update_columns(push_status: "failed", push_error: error_msg)
    else
      Rails.logger.warn("StoreListingPushJob: Could not record error — listing #{store_listing_id} not found")
    end
  end
end
