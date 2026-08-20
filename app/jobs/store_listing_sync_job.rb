class StoreListingSyncJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ArgumentError

  ALLOWED_LISTABLE_TYPES = %w[AppleApp AndroidApp].freeze

  # Imports store listing data from App Store Connect or Google Play
  # into local StoreListing records.
  #
  # @param organization_id [Integer]
  # @param listable_type [String] "AppleApp" or "AndroidApp"
  # @param listable_id [Integer]
  def perform(organization_id:, listable_type:, listable_id:)
    raise ArgumentError, "Unsupported listable type: #{listable_type}" unless ALLOWED_LISTABLE_TYPES.include?(listable_type)

    organization = Organization.find_by(id: organization_id)
    return unless organization

    listable = case listable_type
    when "AppleApp" then AppleApp.find_by(id: listable_id)
    when "AndroidApp" then AndroidApp.find_by(id: listable_id)
    end
    return unless listable

    case listable_type
    when "AppleApp"
      StoreListingSync::AppleImporter.new(
        organization: organization,
        apple_app: listable
      ).import!
    when "AndroidApp"
      StoreListingSync::GoogleImporter.new(
        organization: organization,
        android_app: listable
      ).import!
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn("StoreListingSyncJob: Record not found - #{e.message}")
  rescue StandardError => e
    Rails.logger.error("StoreListingSyncJob failed: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
    raise
  end
end
