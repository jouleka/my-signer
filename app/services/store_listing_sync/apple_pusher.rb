module StoreListingSync
  class ApplePusher
    # Pushes local StoreListing changes to App Store Connect.
    # Updates two ASC resources:
    #   - appInfoLocalizations: name, subtitle (via AppInfo service)
    #   - appStoreVersionLocalizations: description, keywords, whatsNew, etc. (via Versions service)
    #
    # Field editability per Apple docs:
    #   - promotionalText: always editable on any version, does not require App Review
    #   - description, keywords, whatsNew, marketingUrl, supportUrl: only editable when
    #     version is in METADATA_EDITABLE_STATES
    #   - IN_REVIEW / WAITING_FOR_REVIEW: all version-level fields are locked

    # States where version-level metadata (description, keywords, whatsNew, URLs) can be edited
    METADATA_EDITABLE_STATES = %w[
      PREPARE_FOR_SUBMISSION
      READY_FOR_REVIEW
      INVALID_BINARY
      DEVELOPER_REJECTED
      REJECTED
      METADATA_REJECTED
    ].freeze

    def initialize(organization:, store_listing:)
      @organization = organization
      @store_listing = store_listing
      @apple_app = store_listing.listable
      @credential = organization.app_store_connect_credentials.find_by(active: true)
      raise "No active App Store Connect credential" unless @credential
      raise "Store listing is not for an iOS app" unless store_listing.ios?
    end

    # @return [Hash] Push result with :status, :skipped_fields, :version_state
    def push!
      client = AppStoreConnect::Client.new(credential: @credential)
      @result = { skipped_fields: [], version_state: nil, pushed_fields: [] }

      push_app_info!(client)
      push_version_localization!(client)

      fully_synced = @result[:skipped_fields].empty?

      @store_listing.update!(
        sync_status: fully_synced ? "synced" : "partially_synced",
        last_synced_at: Time.current,
        push_status: fully_synced ? "success" : "partial_success",
        push_error: nil,
        push_fields_skipped: @result[:skipped_fields],
        last_pushed_at: Time.current
      )

      @result.merge(status: fully_synced ? "success" : "partial_success")
    end

    private

    def push_app_info!(client)
      app_info_service = AppStoreConnect::AppInfo.new(client)

      attrs = {}
      attrs[:name] = @store_listing.app_name if @store_listing.app_name.present?
      attrs[:subtitle] = @store_listing.subtitle if @store_listing.subtitle.present?

      return if attrs.empty?

      attempt_push_app_info!(app_info_service, attrs)
    end

    # Push app-info attrs with automatic retry-without-rejected-fields. Apple
    # rejects writes to `name` and `subtitle` when the latest app version is
    # not in an editable state (e.g., READY_FOR_SALE). The error message is
    # "There is a problem with the request entity: The field 'X' can not be
    # modified in the current state." We parse the offending field, drop it
    # from the payload, mark it as skipped, and retry. Mirrors the version
    # localization retry pattern below.
    def attempt_push_app_info!(app_info_service, attrs)
      app_info_service.update_by_locale(
        app_id: @apple_app.app_store_id,
        locale: @store_listing.locale,
        **attrs
      )
    rescue StandardError => e
      rejected_field = extract_unmodifiable_app_info_field(e.message)
      raise unless rejected_field && attrs.key?(rejected_field)

      attrs.delete(rejected_field)
      @result[:skipped_fields] << rejected_field.to_s

      return if attrs.empty?

      attempt_push_app_info!(app_info_service, attrs)
    end

    # Parse Apple error like "The field 'name' can not be modified in the
    # current state." and return the matching kwarg key. Returns nil if the
    # message isn't recognized so the original error propagates.
    APP_INFO_ATTR_TO_KEY = {
      "name" => :name,
      "subtitle" => :subtitle,
      "privacyPolicyUrl" => :privacy_policy_url
    }.freeze

    def extract_unmodifiable_app_info_field(message)
      return nil unless message =~ /field '(\w+)' can ?not be modified/i
      APP_INFO_ATTR_TO_KEY[$1]
    end

    def push_version_localization!(client)
      versions_service = AppStoreConnect::Versions.new(client)

      # Find the latest editable version
      versions = versions_service.editable_versions(app_id: @apple_app.app_store_id)
      version = versions.first

      unless version
        # No editable version — track all version-level fields as skipped
        version_fields = %w[description keywords whats_new promotional_text support_url marketing_url]
        skipped = version_fields.select { |f| @store_listing.send(f).present? }
        @result[:skipped_fields].concat(skipped)
        return
      end

      version_state = version.dig("attributes", "appStoreState")
      @result[:version_state] = version_state
      metadata_editable = METADATA_EDITABLE_STATES.include?(version_state)

      # Track which fields are being skipped due to version state
      unless metadata_editable
        skipped = []
        skipped << "description" if @store_listing.description.present?
        skipped << "keywords" if @store_listing.keywords.present?
        skipped << "whats_new" if @store_listing.whats_new.present?
        skipped << "support_url" if @store_listing.support_url.present?
        skipped << "marketing_url" if @store_listing.marketing_url.present?
        @result[:skipped_fields].concat(skipped)
      end

      # Check if localization exists for this locale
      localizations = versions_service.localizations(version_id: version["id"])
      existing = localizations.find { |l| l.dig("attributes", "locale") == @store_listing.locale }

      attrs = build_version_localization_attrs(metadata_editable: metadata_editable)
      @result[:pushed_fields] = attrs.keys.map(&:to_s)
      return if attrs.empty?

      push_localization_with_retry!(versions_service, version, existing, attrs)
    end

    # Push localization attributes, automatically retrying without fields that Apple rejects.
    # Apple may reject specific attributes depending on version state (e.g. whatsNew on first
    # version, or fields locked during review) — this handles all such cases gracefully.
    def push_localization_with_retry!(versions_service, version, existing, attrs)
      attempt_push_localization!(versions_service, version, existing, attrs)
    rescue StandardError => e
      rejected_field = extract_rejected_field(e.message)
      raise unless rejected_field && attrs.key?(rejected_field)

      # Remove the rejected field and track it as skipped
      attrs.delete(rejected_field)
      @result[:skipped_fields] << rejected_field.to_s
      @result[:pushed_fields] = attrs.keys.map(&:to_s)

      return if attrs.empty?

      # Retry — may need multiple rounds if several fields are rejected
      push_localization_with_retry!(versions_service, version, existing, attrs)
    end

    def attempt_push_localization!(versions_service, version, existing, attrs)
      if existing
        versions_service.update_localization(localization_id: existing["id"], **attrs)
      else
        versions_service.create_localization(version_id: version["id"], locale: @store_listing.locale, **attrs)
      end
    end

    # Maps Apple's camelCase attribute names from error messages to our snake_case kwarg keys
    APPLE_ATTR_TO_KEY = {
      "whatsNew" => :whats_new,
      "description" => :description,
      "keywords" => :keywords,
      "promotionalText" => :promotional_text,
      "marketingUrl" => :marketing_url,
      "supportUrl" => :support_url
    }.freeze

    # Parse Apple error like "Attribute 'whatsNew' cannot be edited at this time"
    def extract_rejected_field(message)
      return nil unless message =~ /Attribute '(\w+)' cannot be edited/
      APPLE_ATTR_TO_KEY[$1]
    end

    def build_version_localization_attrs(metadata_editable: false)
      attrs = {}

      # promotionalText can always be updated regardless of version state
      attrs[:promotional_text] = @store_listing.promotional_text unless @store_listing.promotional_text.nil?

      # All other version-level fields require the version to be in an editable state
      if metadata_editable
        attrs[:description] = @store_listing.description unless @store_listing.description.nil?
        attrs[:keywords] = @store_listing.keywords unless @store_listing.keywords.nil?
        attrs[:whats_new] = @store_listing.whats_new unless @store_listing.whats_new.nil?
        attrs[:support_url] = @store_listing.support_url unless @store_listing.support_url.nil?
        attrs[:marketing_url] = @store_listing.marketing_url unless @store_listing.marketing_url.nil?
      end

      attrs
    end
  end
end
