module StoreListingSync
  class AppleImporter
    # Imports store listing metadata from App Store Connect into local StoreListing records.
    # Combines data from two ASC resources:
    #   - appInfoLocalizations: name, subtitle
    #   - appStoreVersionLocalizations: description, keywords, whatsNew, promotionalText, etc.

    def initialize(organization:, apple_app:)
      @organization = organization
      @apple_app = apple_app
      @credential = organization.app_store_connect_credentials.find_by(active: true)
      raise "No active App Store Connect credential" unless @credential
    end

    # @return [Array<StoreListing>] Created or updated store listings
    def import!
      client = AppStoreConnect::Client.new(credential: @credential)
      app_info_service = AppStoreConnect::AppInfo.new(client)
      versions_service = AppStoreConnect::Versions.new(client)

      # Fetch app-level localizations (name, subtitle)
      app_info = app_info_service.primary(app_id: @apple_app.app_store_id)
      app_info_localizations = app_info ? app_info_service.localizations(app_info_id: app_info["id"]) : []

      # Fetch version-level localizations (description, keywords, whatsNew, etc.)
      # Prefer an editable version when one exists; otherwise fall back to the
      # latest version regardless of state. Apple permits READING localizations
      # from any state — only writes are state-gated. Without this fallback,
      # apps whose latest version is READY_FOR_SALE would import no version data.
      version = readable_version(versions_service)
      version_localizations = version ? versions_service.localizations(version_id: version["id"]) : []

      # Build a merged map of locale -> fields from both sources
      locale_data = merge_localizations(app_info_localizations, version_localizations)

      # Upsert StoreListing records (without final timestamp — set after screenshots)
      sync_time = Time.current
      imported = []
      ApplicationRecord.transaction do
        locale_data.each do |locale, fields|
          listing = @apple_app.store_listings.find_or_initialize_by(locale: locale)
          listing.organization = @organization
          listing.assign_attributes(
            app_name: fields[:name],
            subtitle: fields[:subtitle],
            keywords: fields[:keywords],
            description: fields[:description],
            promotional_text: fields[:promotional_text],
            whats_new: fields[:whats_new],
            support_url: fields[:support_url],
            marketing_url: fields[:marketing_url],
            privacy_policy_url: fields[:privacy_policy_url],
            sync_status: "synced"
          )
          listing.save!
          imported << listing
        end
      end

      # Best-effort screenshot sync (runs before we stamp last_synced_at)
      sync_screenshots!(client, version_localizations) if version

      # Stamp last_synced_at AFTER screenshots are done so the UI poller
      # doesn't reload the page before screenshots have been saved
      @apple_app.store_listings.where(locale: locale_data.keys)
        .update_all(last_synced_at: Time.current)

      imported
    end

    private

    def sync_screenshots!(_client, version_localizations)
      # Fan out per-locale. Each locale requires one "list screenshot sets"
      # call + N "list screenshots" calls (one per display type). Locales
      # are fully independent of each other, so we parallelize across
      # locales. Each future gets its own Client — Faraday's Net::HTTP
      # adapter isn't safe to share across concurrent requests on one
      # connection.
      ::Sync::ParallelFanout.call(version_localizations) do |loc|
        fetch_screenshots_for_locale(loc)
      end
    end

    def fetch_screenshots_for_locale(loc)
      attrs = loc["attributes"] || {}
      locale = attrs["locale"]
      return unless locale

      listing = @apple_app.store_listings.find_by(locale: locale)
      return unless listing

      client = AppStoreConnect::Client.new(credential: @credential)
      screenshots_service = AppStoreConnect::Screenshots.new(client)

      screenshot_sets = screenshots_service.list_screenshot_sets(localization_id: loc["id"])
      screenshots = []

      screenshot_sets.each do |set|
        display_type = set.dig("attributes", "screenshotDisplayType")
        set_screenshots = screenshots_service.list_screenshots(set_id: set["id"])

        set_screenshots.each do |ss|
          ss_attrs = ss["attributes"] || {}
          template_url = ss_attrs.dig("imageAsset", "templateUrl")
          next unless template_url.present?

          width = ss_attrs.dig("imageAsset", "width") || 300
          height = ss_attrs.dig("imageAsset", "height") || 600
          thumb_w = [ width, 230 ].min
          thumb_h = (thumb_w.to_f / width * height).round
          url = template_url.gsub("{w}", thumb_w.to_s).gsub("{h}", thumb_h.to_s).gsub("{f}", "png")

          screenshots << {
            "url" => url,
            "width" => width,
            "height" => height,
            "display_type" => display_type
          }
        end
      end

      listing.update_column(:metadata, listing.metadata.merge("screenshots" => screenshots))
    rescue StandardError => e
      Rails.logger.warn("AppleImporter: Failed to sync screenshots for locale #{loc.dig('attributes', 'locale')}: #{e.message}")
    end

    # Returns the version we should READ localizations from. Prefers an
    # editable version (so the user can both view and write metadata), and
    # falls back to the latest live version when no editable one exists.
    def readable_version(versions_service)
      editable = versions_service.editable_versions(app_id: @apple_app.app_store_id).first
      return editable if editable

      versions_service.latest_version(app_id: @apple_app.app_store_id)
    end

    def merge_localizations(app_info_locs, version_locs)
      data = {}

      # App info localizations: name, subtitle, privacyPolicyUrl
      app_info_locs.each do |loc|
        attrs = loc["attributes"] || {}
        locale = attrs["locale"]
        next unless locale

        data[locale] ||= {}
        data[locale][:name] = attrs["name"]
        data[locale][:subtitle] = attrs["subtitle"]
        data[locale][:privacy_policy_url] = attrs["privacyPolicyUrl"]
      end

      # Version localizations: description, keywords, whatsNew, promotionalText, etc.
      version_locs.each do |loc|
        attrs = loc["attributes"] || {}
        locale = attrs["locale"]
        next unless locale

        data[locale] ||= {}
        data[locale][:description] = attrs["description"]
        data[locale][:keywords] = attrs["keywords"]
        data[locale][:whats_new] = attrs["whatsNew"]
        data[locale][:promotional_text] = attrs["promotionalText"]
        data[locale][:support_url] = attrs["supportUrl"]
        data[locale][:marketing_url] = attrs["marketingUrl"]
      end

      data
    end
  end
end
