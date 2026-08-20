class ReleaseChecklist
  # Detects release-blocking and release-impacting issues from existing data
  # in the database (no new API calls). Returns issues as checklist item hashes
  # that the existing checklist UI can render alongside default and custom
  # items.
  #
  # Each detected issue conforms to this contract:
  # {
  #   "key" => String (unique, deterministic, prefixed with "auto_"),
  #   "label" => String (short, human-readable),
  #   "detail" => String (longer explanation),
  #   "severity" => "error" | "warning" | "info",
  #   "required" => Boolean (true blocks push),
  #   "checked" => false (auto items resolve when the condition clears),
  #   "auto_detected" => true,
  #   "source" => "app_store_connect" | "google_play" | "local_check",
  #   "action_url" => nil | String,
  #   "category" => "issue"
  # }
  class AutoDetector
    SHORT_DESCRIPTION_THRESHOLD = 20

    # @param organization [Organization]
    # @param app [AppleApp, AndroidApp]
    # @param checklist [ReleaseChecklist, nil] optional; when present, used to
    #   pin per-version rules (e.g., release notes char limit) to the
    #   checklist's version_string.
    def initialize(organization:, app:, checklist: nil)
      @checklist = checklist
      @organization = organization
      @app = app
    end

    # @return [Array<Hash>] auto-detected items in the standard contract shape
    def detect
      return [] unless @app && @organization

      items = []
      rules.each do |rule|
        result = send(rule)
        case result
        when Array then items.concat(result.compact)
        when Hash  then items << result
        end
      end
      items.compact
    end

    private

    attr_reader :checklist, :organization, :app

    def rules
      if ios?
        ios_rules + shared_rules
      elsif android?
        android_rules + shared_rules
      else
        []
      end
    end

    def ios_rules
      %i[
        check_ios_rejected_version
        check_ios_invalid_binary
        check_ios_missing_privacy_url
        check_ios_missing_support_url
        check_ios_build_not_attached
        check_ios_encryption_compliance_unset
        check_ios_pre_submission_validation_errors
      ]
    end

    def android_rules
      %i[
        check_android_rollout_halted
      ]
    end

    def shared_rules
      %i[
        check_missing_description
        check_release_notes_over_char_limit
        check_release_notes_missing_for_version
        check_untranslated_locales
        check_description_too_short
      ]
    end

    def ios?
      app.is_a?(AppleApp)
    end

    def android?
      app.is_a?(AndroidApp)
    end

    # === iOS rules ===

    def check_ios_rejected_version
      version = app.app_store_versions.order(created_at: :desc).first
      return nil unless version
      return nil unless %w[REJECTED METADATA_REJECTED DEVELOPER_REJECTED].include?(version.app_store_state)

      label = case version.app_store_state
      when "REJECTED" then "App Store rejected version #{version.version_string}"
      when "METADATA_REJECTED" then "App Store rejected metadata for version #{version.version_string}"
      when "DEVELOPER_REJECTED" then "Version #{version.version_string} was rejected by you"
      end

      action_url = if app.respond_to?(:app_store_id) && app.app_store_id.present?
                     "https://appstoreconnect.apple.com/apps/#{app.app_store_id}/appstore"
      end

      {
        "key" => "auto_ios_rejected_#{version.id}",
        "label" => label,
        "detail" => "Apple does not expose rejection reasons via the API. Open App Store Connect > Resolution Center to see the specific feedback.",
        "severity" => "error",
        "required" => true,
        "checked" => false,
        "auto_detected" => true,
        "source" => "app_store_connect",
        "action_url" => action_url,
        "category" => "issue"
      }
    end

    def check_ios_invalid_binary
      version = app.app_store_versions.order(created_at: :desc).first
      return nil unless version&.app_store_state == "INVALID_BINARY"

      {
        "key" => "auto_ios_invalid_binary_#{version.id}",
        "label" => "Invalid binary for version #{version.version_string}",
        "detail" => "Apple rejected the uploaded build as invalid. Check Xcode signing, provisioning profile, or entitlements and re-upload.",
        "severity" => "error",
        "required" => true,
        "checked" => false,
        "auto_detected" => true,
        "source" => "app_store_connect",
        "action_url" => nil,
        "category" => "issue"
      }
    end

    def check_ios_missing_privacy_url
      listing = primary_store_listing
      return nil unless listing
      return nil if listing.privacy_policy_url.present?

      {
        "key" => "auto_ios_missing_privacy_url",
        "label" => "Privacy Policy URL missing (iOS)",
        "detail" => "Apple requires a Privacy Policy URL on every app listing. Add one in the Listing tab.",
        "severity" => "error",
        "required" => true,
        "checked" => false,
        "auto_detected" => true,
        "source" => "local_check",
        "action_url" => nil,
        "category" => "issue"
      }
    end

    def check_ios_missing_support_url
      listing = primary_store_listing
      return nil unless listing
      return nil if listing.support_url.present?

      {
        "key" => "auto_ios_missing_support_url",
        "label" => "Support URL missing (iOS)",
        "detail" => "Apple requires a Support URL on every app listing. Add one in the Listing tab.",
        "severity" => "error",
        "required" => true,
        "checked" => false,
        "auto_detected" => true,
        "source" => "local_check",
        "action_url" => nil,
        "category" => "issue"
      }
    end

    def check_ios_build_not_attached
      version = app.app_store_versions
                   .where(app_store_state: "PREPARE_FOR_SUBMISSION")
                   .order(created_at: :desc)
                   .first
      return nil unless version
      return nil if version.apple_build_id.present?

      {
        "key" => "auto_ios_no_build_#{version.id}",
        "label" => "No build attached to version #{version.version_string}",
        "detail" => "The in-progress App Store version has no build selected. Upload and attach a build before submission.",
        "severity" => "error",
        "required" => true,
        "checked" => false,
        "auto_detected" => true,
        "source" => "app_store_connect",
        "action_url" => nil,
        "category" => "issue"
      }
    end

    def check_ios_encryption_compliance_unset
      build = app.apple_builds.order(created_at: :desc).first
      return nil unless build

      raw = build.raw_json
      attrs = raw.is_a?(Hash) ? (raw["attributes"] || raw[:attributes]) : nil
      uses_encryption =
        if attrs.is_a?(Hash)
          val = attrs["usesNonExemptEncryption"]
          val.nil? ? attrs[:usesNonExemptEncryption] : val
        end

      # Only flag when truly unset (nil) — not when explicitly true or false.
      return nil unless uses_encryption.nil?

      {
        "key" => "auto_ios_encryption_unset_#{build.id}",
        "label" => "Export compliance not declared",
        "detail" => "The latest build does not have an export compliance declaration. Apple requires you to answer whether the app uses encryption.",
        "severity" => "warning",
        "required" => false,
        "checked" => false,
        "auto_detected" => true,
        "source" => "app_store_connect",
        "action_url" => nil,
        "category" => "issue"
      }
    end

    # Phase 2 rule: reads pre-submission validation errors fetched from Apple's
    # appStoreVersionSubmission include during sync and stored in
    # `app_store_versions.issues` (JSONB array). Emits ONE auto-detected item
    # per validation error. Each stored issue has the shape
    # `{"code" => String, "detail" => String, "raw" => Hash}`.
    def check_ios_pre_submission_validation_errors
      items = []
      app.app_store_versions.find_each do |version|
        next unless version.respond_to?(:issues)
        stored = version.issues
        next if stored.blank?
        next unless stored.is_a?(Array)

        stored.each_with_index do |issue, idx|
          next unless issue.is_a?(Hash)

          code = issue["code"].presence || issue[:code].presence
          detail = issue["detail"].presence || issue[:detail].presence || issue["title"] || "Apple reported a validation error."
          # Build a deterministic key from code or index so the same issue
          # doesn't create duplicate items across re-renders.
          key_suffix = code.presence || "err#{idx}"

          label = if code.present? && code != "UNKNOWN"
                    "Apple validation: #{code.to_s.tr('_', ' ').downcase.capitalize}"
          else
                    "Apple validation error on v#{version.version_string}"
          end

          items << {
            "key" => "auto_ios_validation_#{version.id}_#{key_suffix}",
            "label" => label,
            "detail" => detail.to_s,
            "severity" => "error",
            "required" => true,
            "checked" => false,
            "auto_detected" => true,
            "source" => "app_store_connect",
            "action_url" => nil,
            "category" => "issue"
          }
        end
      end
      items
    end

    # === Android rules ===

    def check_android_rollout_halted
      return nil unless app.respond_to?(:android_tracks)

      halted = []
      app.android_tracks.find_each do |track|
        raw = track.raw_json
        next unless raw.is_a?(Hash)

        releases = raw["releases"] || raw[:releases] || []
        next unless releases.is_a?(Array)

        releases.each do |release|
          next unless release.is_a?(Hash)
          status = release["status"] || release[:status]
          next unless status == "halted"

          halted << {
            track: track.track_name,
            version_codes: release["versionCodes"] || release[:versionCodes]
          }
        end
      end
      return nil if halted.empty?

      {
        "key" => "auto_android_rollout_halted",
        "label" => "Google Play rollout is halted",
        "detail" => "One or more releases are in 'halted' state on Google Play. This usually means Google detected a crash spike. Investigate in Play Console.",
        "severity" => "error",
        "required" => true,
        "checked" => false,
        "auto_detected" => true,
        "source" => "google_play",
        "action_url" => nil,
        "category" => "issue"
      }
    end

    # === Shared rules ===

    def check_missing_description
      listing = primary_store_listing
      return nil unless listing
      return nil if listing.description.present?

      {
        "key" => "auto_missing_description",
        "label" => "App description is empty",
        "detail" => "The primary locale listing has no description. This is required by both stores.",
        "severity" => "error",
        "required" => true,
        "checked" => false,
        "auto_detected" => true,
        "source" => "local_check",
        "action_url" => nil,
        "category" => "issue"
      }
    end

    def check_release_notes_over_char_limit
      note = checklist_release_note
      return nil if note.nil?
      return nil if note.rendered_text.blank?

      limit = note.char_limit
      return nil unless limit && note.rendered_text.length > limit

      platform_label = ios? ? "Apple" : "Google Play"
      {
        "key" => "auto_release_notes_over_limit_#{note.id}",
        "label" => "Release notes exceed #{limit}-character limit",
        "detail" => "Current release notes are #{note.rendered_text.length} characters. #{platform_label} limits this to #{limit}. Shorten in the What's New tab.",
        "severity" => "error",
        "required" => true,
        "checked" => false,
        "auto_detected" => true,
        "source" => "local_check",
        "action_url" => nil,
        "category" => "issue"
      }
    end

    def check_release_notes_missing_for_version
      # If we have a synced iOS version or Android release with a version_string,
      # but no ReleaseNote exists for that version, flag it.
      return nil if ios? && app.app_store_versions.empty?
      return nil if android? && app.play_store_releases.empty?

      target_version = if ios?
                         app.app_store_versions.order(created_at: :desc).first&.version_string
      else
                         app.play_store_releases.order(created_at: :desc).first&.version_code
      end
      return nil if target_version.blank?

      exists = organization.release_notes.for_app(app).where(version_string: target_version).exists?
      return nil if exists

      {
        "key" => "auto_release_notes_missing_for_#{target_version}",
        "label" => "No release notes for version #{target_version}",
        "detail" => "The current store version has no matching release notes in MySigner. Create one in the What's New tab.",
        "severity" => "warning",
        "required" => false,
        "checked" => false,
        "auto_detected" => true,
        "source" => "local_check",
        "action_url" => nil,
        "category" => "issue"
      }
    end

    def check_untranslated_locales
      return nil unless app.respond_to?(:store_listings)

      pending_count = organization.store_listings
                                  .where(listable: app, translation_status: "needs_review")
                                  .count
      return nil if pending_count.zero?

      {
        "key" => "auto_untranslated_locales",
        "label" => "#{pending_count} locale(s) need translation review",
        "detail" => "Some locales have translations that haven't been approved yet. Review them in the Listing tab locale switcher.",
        "severity" => "info",
        "required" => false,
        "checked" => false,
        "auto_detected" => true,
        "source" => "local_check",
        "action_url" => nil,
        "category" => "issue"
      }
    end

    def check_description_too_short
      listing = primary_store_listing
      return nil unless listing
      return nil if listing.description.blank?
      return nil if listing.description.strip.length >= SHORT_DESCRIPTION_THRESHOLD

      {
        "key" => "auto_description_too_short",
        "label" => "Description is very short",
        "detail" => "Your app description is only #{listing.description.strip.length} characters. Longer descriptions improve conversion and ASO.",
        "severity" => "info",
        "required" => false,
        "checked" => false,
        "auto_detected" => true,
        "source" => "local_check",
        "action_url" => nil,
        "category" => "issue"
      }
    end

    # === Helpers ===

    def primary_store_listing
      return nil unless app.respond_to?(:store_listings)

      # Read the primary locale from the synced app data (Apple's primaryLocale
      # or Google's default_language). Falls back to any existing listing if
      # the primary locale has no matching record.
      primary = app&.primary_locale

      organization.store_listings.where(listable: app).find_by(locale: primary) ||
        organization.store_listings.where(listable: app).first
    end

    def checklist_release_note
      # Find the release note that matches the checklist's version_string,
      # falling back to the latest draft for the app.
      return nil unless checklist&.version_string.present?

      organization.release_notes.for_app(app).find_by(version_string: checklist.version_string) ||
        organization.release_notes.for_app(app).drafts.first
    end
  end
end
