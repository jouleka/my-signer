# frozen_string_literal: true

module AppStoreConnect
  # Service for managing App Info (metadata that lives on the app level, not the version level)
  # This includes keywords, subtitle, privacy text, category info, etc.
  # These fields are managed via appInfos and appInfoLocalizations resources.
  class AppInfo
    def initialize(client)
      @client = client
    end

    # Get all app infos for an app
    # @param app_id [String] Apple app store ID
    # @return [Array<Hash>] App info objects
    def list(app_id:)
      response = @client.get("apps/#{app_id}/appInfos")
      response["data"] || []
    end

    # Get the primary (most recent) app info
    # @param app_id [String] Apple app store ID
    # @return [Hash, nil] App info object
    def primary(app_id:)
      infos = list(app_id: app_id)
      # Primary is typically the first one, or filter by state if needed
      infos.first
    end

    # Get localizations for an app info
    # @param app_info_id [String] App info ID from Apple
    # @return [Array<Hash>] Localizations
    def localizations(app_info_id:)
      response = @client.get("appInfos/#{app_info_id}/appInfoLocalizations")
      response["data"] || []
    end

    # Create a new app info localization
    # @param app_info_id [String] App info ID from Apple
    # @param locale [String] Locale code (e.g., "en-US")
    # @param name [String, nil] App name
    # @param subtitle [String, nil] App subtitle
    # @param privacy_policy_text [String, nil] Privacy policy text
    # @param privacy_choices_url [String, nil] Privacy choices URL
    # @param privacy_policy_url [String, nil] Privacy policy URL
    # @return [Hash] Created localization data
    def create_localization(app_info_id:, locale: "en-US", name: nil, subtitle: nil,
                            privacy_policy_text: nil, privacy_choices_url: nil, privacy_policy_url: nil)
      attributes = { locale: locale }
      attributes[:name] = name if name
      attributes[:subtitle] = subtitle if subtitle
      attributes[:privacyPolicyText] = privacy_policy_text if privacy_policy_text
      attributes[:privacyChoicesUrl] = privacy_choices_url if privacy_choices_url
      attributes[:privacyPolicyUrl] = privacy_policy_url if privacy_policy_url

      payload = {
        data: {
          type: "appInfoLocalizations",
          attributes: attributes,
          relationships: {
            appInfo: {
              data: {
                type: "appInfos",
                id: app_info_id
              }
            }
          }
        }
      }
      @client.post("appInfoLocalizations", json: payload)
    end

    # Update an existing app info localization
    # @param localization_id [String] Localization ID from Apple
    # @param name [String, nil] App name
    # @param subtitle [String, nil] App subtitle
    # @param privacy_policy_text [String, nil] Privacy policy text
    # @param privacy_choices_url [String, nil] Privacy choices URL
    # @param privacy_policy_url [String, nil] Privacy policy URL
    # @return [Hash] Updated localization data
    def update_localization(localization_id:, name: nil, subtitle: nil,
                            privacy_policy_text: nil, privacy_choices_url: nil, privacy_policy_url: nil)
      attributes = {}
      attributes[:name] = name unless name.nil?
      attributes[:subtitle] = subtitle unless subtitle.nil?
      attributes[:privacyPolicyText] = privacy_policy_text unless privacy_policy_text.nil?
      attributes[:privacyChoicesUrl] = privacy_choices_url unless privacy_choices_url.nil?
      attributes[:privacyPolicyUrl] = privacy_policy_url unless privacy_policy_url.nil?

      payload = {
        data: {
          type: "appInfoLocalizations",
          id: localization_id,
          attributes: attributes
        }
      }
      @client.patch("appInfoLocalizations/#{localization_id}", json: payload)
    end

    # Update keywords for an app
    # Keywords are NOT part of appInfoLocalizations - they are part of appStoreVersionLocalizations
    # But subtitle and other app-level metadata are in appInfoLocalizations.
    # This method updates the subtitle for a given locale.
    # @param app_id [String] Apple app store ID
    # @param locale [String] Locale code (e.g., "en-US")
    # @param subtitle [String] App subtitle (max 30 chars)
    # @return [Hash] Updated or created localization
    def update_subtitle(app_id:, locale: "en-US", subtitle:)
      app_info = primary(app_id: app_id)
      return nil unless app_info

      localizations_list = localizations(app_info_id: app_info["id"])
      existing = localizations_list.find { |loc| loc.dig("attributes", "locale") == locale }

      if existing
        update_localization(
          localization_id: existing["id"],
          subtitle: subtitle
        )
      else
        create_localization(
          app_info_id: app_info["id"],
          locale: locale,
          subtitle: subtitle
        )
      end
    end

    # Get or find localization for a specific locale
    # @param app_id [String] Apple app store ID
    # @param locale [String] Locale code (e.g., "en-US")
    # @return [Hash, nil] Localization data or nil
    def find_localization(app_id:, locale: "en-US")
      app_info = primary(app_id: app_id)
      return nil unless app_info

      localizations_list = localizations(app_info_id: app_info["id"])
      localizations_list.find { |loc| loc.dig("attributes", "locale") == locale }
    end

    # Update app info localization by app_id and locale
    # Creates the localization if it doesn't exist
    # @param app_id [String] Apple app store ID
    # @param locale [String] Locale code (e.g., "en-US")
    # @param attributes [Hash] Attributes to update (:subtitle, :name, etc.)
    # @return [Hash] Updated or created localization
    def update_by_locale(app_id:, locale: "en-US", **attributes)
      app_info = primary(app_id: app_id)
      raise "No app info found for app #{app_id}" unless app_info

      localizations_list = localizations(app_info_id: app_info["id"])
      existing = localizations_list.find { |loc| loc.dig("attributes", "locale") == locale }

      if existing
        update_localization(localization_id: existing["id"], **attributes)
      else
        create_localization(app_info_id: app_info["id"], locale: locale, **attributes)
      end
    end
  end
end
