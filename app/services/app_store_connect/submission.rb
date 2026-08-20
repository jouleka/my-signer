module AppStoreConnect
  class Submission
    # Handles the complete App Store submission workflow
    def initialize(credential:)
      @credential = credential
      @client = AppStoreConnect::Client.new(credential: credential)
      @versions = AppStoreConnect::Versions.new(@client)
    end

    # Submit a build for App Store review
    # @param app_store_id [String] Apple app store ID
    # @param build_id [String] Apple build ID
    # @param version_string [String] Version number
    # @param metadata [Hash] Metadata (whats_new, support_url, etc.)
    # @return [Hash] Result with version and submission info
    def submit(app_store_id:, build_id:, version_string: nil, metadata: {})
      # Step 1: Find or create editable version
      editable_versions = @versions.editable_versions(app_id: app_store_id)

      version = if editable_versions.any?
        editable_versions.first
      else
        # Create new version
        response = @versions.create(
          app_id: app_store_id,
          version_string: version_string || Time.now.strftime("%Y.%m.%d"),
          platform: "IOS"
        )
        response["data"]
      end

      version_id = version["id"]

      # Step 2: Attach build to version
      @versions.attach_build(version_id: version_id, build_id: build_id)

      # Step 3: Update localization with What's New text (if provided)
      if metadata[:whats_new].present?
        # Resolve locale from metadata, then from the app's actual primary locale,
        # then fall back to en-US only if neither is available.
        resolved_locale = metadata[:locale].presence ||
                          @credential.organization.apple_apps.find_by(app_store_id: app_store_id)&.primary_locale ||
                          "en-US"
        update_or_create_localization(
          version_id: version_id,
          locale: resolved_locale,
          whats_new: metadata[:whats_new],
          keywords: metadata[:keywords],
          marketing_url: metadata[:marketing_url],
          promotional_text: metadata[:promotional_text],
          support_url: metadata[:support_url]
        )
      end

      # Step 4: Submit for review
      submission = @versions.submit_for_review(
        app_id: app_store_id,
        version_id: version_id,
        platform: metadata[:platform] || "IOS"
      )

      {
        success: true,
        version: version,
        submission: submission
      }
    end

    private

    def update_or_create_localization(version_id:, locale:, **attributes)
      # Get existing localizations
      localizations = @versions.localizations(version_id: version_id)

      # Find matching locale
      existing = localizations.find { |loc| loc.dig("attributes", "locale") == locale }

      if existing
        # Update existing
        @versions.update_localization(
          localization_id: existing["id"],
          **attributes.compact
        )
      else
        # Create new
        @versions.create_localization(
          version_id: version_id,
          locale: locale,
          **attributes.compact
        )
      end
    end
  end
end
