module StoreListingSync
  class GoogleImporter
    # Imports store listing metadata from Google Play into local StoreListing records.

    def initialize(organization:, android_app:, client: nil)
      @organization = organization
      @android_app = android_app
      @credential = organization.google_play_credentials.find_by(active: true)
      raise "No active Google Play credential" unless @credential
      # Accept an injected client so the caller (the sync job) can build one
      # client per job run and reuse it across all apps, instead of
      # re-authenticating a fresh ServiceAccountCredentials per app.
      @injected_client = client
    end

    # @return [Array<StoreListing>] Created or updated store listings
    def import!
      client = @injected_client || GooglePlay::Client.new(credential: @credential)
      listings_service = GooglePlay::Listings.new(client)

      listings = listings_service.list(@android_app.package_name)

      imported = []
      locales = []
      ApplicationRecord.transaction do
        listings.each do |listing_data|
          raw_locale = listing_data[:language]
          next if raw_locale.blank?

          # Normalize underscore format (pt_BR) to hyphen format (pt-BR)
          # to match our canonical StoreListing.locale storage format.
          locale = raw_locale.to_s.strip.tr("_", "-")
          next if locale.blank?

          listing = @android_app.store_listings.find_or_initialize_by(locale: locale)
          listing.organization = @organization
          listing.assign_attributes(
            app_name: listing_data[:title],
            short_description: listing_data[:short_description],
            description: listing_data[:full_description],
            sync_status: "synced"
          )
          listing.save!
          imported << listing
          locales << locale
        end
      end

      # Best-effort screenshot sync — scoped to locales from this run so we
      # don't overwrite screenshots for stale listings from previous syncs.
      sync_screenshots!(client, locales: locales)

      # Stamp last_synced_at AFTER screenshots are done so the UI poller
      # doesn't reload the page before screenshots have been saved
      @android_app.store_listings.where(locale: locales)
        .update_all(last_synced_at: Time.current)

      imported
    end

    private

    def sync_screenshots!(client, locales: [])
      screenshots_service = GooglePlay::Screenshots.new(client)

      scope = locales.any? ? @android_app.store_listings.where(locale: locales) : @android_app.store_listings
      listings = scope.to_a
      return if listings.empty?

      # One edit per app instead of one edit per locale: we were paying
      # `create_edit` + `delete_edit` round-trips L times. Now: 1 + 1,
      # regardless of locale count.
      edit = begin
        client.create_edit(@android_app.package_name)
      rescue StandardError => e
        Rails.logger.warn("GoogleImporter: Failed to open edit for screenshots: #{e.message}")
        return
      end

      begin
        listings.each do |listing|
          begin
            results = screenshots_service.fetch_current_screenshots_with_edit(
              package_name: @android_app.package_name,
              edit_id: edit.id,
              language: listing.locale
            )

            screenshots = []
            results.each do |image_type, images|
              images.each do |img|
                screenshots << {
                  "url" => img[:url],
                  "image_type" => image_type
                }
              end
            end

            listing.update_column(:metadata, listing.metadata.merge("screenshots" => screenshots))
          rescue StandardError => e
            Rails.logger.warn("GoogleImporter: Failed to sync screenshots for locale #{listing.locale}: #{e.message}")
          end
        end
      ensure
        begin
          client.delete_edit(@android_app.package_name, edit.id)
        rescue StandardError => cleanup_error
          Rails.logger.warn("GoogleImporter: Failed to cleanup screenshot edit: #{cleanup_error.message}")
        end
      end
    end
  end
end
