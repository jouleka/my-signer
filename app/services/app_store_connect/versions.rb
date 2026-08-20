module AppStoreConnect
  class Versions
    # Apple phased release state constants
    PHASED_RELEASE_STATES = {
      can_activate: %w[READY_FOR_SALE PENDING_DEVELOPER_RELEASE],
      pending: %w[IN_REVIEW WAITING_FOR_REVIEW PROCESSING_FOR_APP_STORE],
      removed: %w[DEVELOPER_REMOVED_FROM_SALE REMOVED_FROM_SALE]
    }.freeze

    def initialize(client)
      @client = client
    end

    def list(app_id:, limit: 50, &block)
      @client.paginate("apps/#{app_id}/appStoreVersions", params: { limit: limit }, &block)
    end

    # Create a new App Store version
    # @param app_id [String] Apple app store ID
    # @param version_string [String] Version number (e.g., "1.0.1")
    # @param platform [String] Platform (IOS, MAC_OS, TV_OS)
    # @param release_type [String] Release type (AFTER_APPROVAL, MANUAL, SCHEDULED)
    # @param earliest_release_date [Time, nil] Required if release_type is SCHEDULED
    # @return [Hash] Created version data
    def create(app_id:, version_string:, platform: "IOS", release_type: "AFTER_APPROVAL", earliest_release_date: nil)
      attributes = {
        platform: platform,
        versionString: version_string,
        releaseType: release_type
      }

      if release_type == "SCHEDULED" && earliest_release_date
        attributes[:earliestReleaseDate] = earliest_release_date.to_time.utc.iso8601
      end

      payload = {
        data: {
          type: "appStoreVersions",
          attributes: attributes,
          relationships: {
            app: {
              data: {
                type: "apps",
                id: app_id
              }
            }
          }
        }
      }
      @client.post("appStoreVersions", json: payload)
    end

    # Get editable versions for an app
    # @param app_id [String] Apple app store ID
    # @return [Array<Hash>] Editable versions
    def editable_versions(app_id:)
      # IN_REVIEW is excluded: Apple locks all localization fields during review.
      # WAITING_FOR_REVIEW is included: promotionalText can still be updated.
      editable_states = %w[PREPARE_FOR_SUBMISSION READY_FOR_REVIEW DEVELOPER_REJECTED REJECTED METADATA_REJECTED WAITING_FOR_REVIEW INVALID_BINARY]
      response = @client.get("apps/#{app_id}/appStoreVersions", params: {
        "filter[appStoreState]" => editable_states.join(","),
        limit: 50
      })
      response["data"] || []
    end

    # Get the most recent App Store version regardless of state.
    # Used by the importer to read localizations from a live (READY_FOR_SALE)
    # version when no editable version exists. Apple permits READING
    # localizations from any state, even though writes are state-gated.
    #
    # NOTE: Apple's appStoreVersions endpoint does not accept the `sort`
    # parameter (returns 400). We fetch a page and sort locally by createdDate.
    # @param app_id [String] Apple app store ID
    # @return [Hash, nil] The latest version object, or nil if none exist
    def latest_version(app_id:)
      response = @client.get("apps/#{app_id}/appStoreVersions", params: { limit: 50 })
      versions = response["data"] || []
      return nil if versions.empty?

      versions.max_by { |v| v.dig("attributes", "createdDate").to_s }
    end

    # Attach a build to an App Store version
    # @param version_id [String] App Store version ID from Apple
    # @param build_id [String] Build ID from Apple (not our internal ID)
    # @return [Hash] Response from Apple
    def attach_build(version_id:, build_id:)
      payload = {
        data: {
          type: "builds",
          id: build_id
        }
      }
      @client.patch("appStoreVersions/#{version_id}/relationships/build", json: payload)
    end

    # Add or update localization for a version
    # @param version_id [String] App Store version ID from Apple
    # @param locale [String] Locale code (e.g., "en-US")
    # @param whats_new [String] What's new text
    # @param marketing_url [String] Marketing URL
    # @param promotional_text [String] Promotional text
    # @param support_url [String] Support URL
    # @return [Hash] Localization data
    def create_localization(version_id:, locale: "en-US", description: nil, keywords: nil, whats_new: nil, marketing_url: nil, promotional_text: nil, support_url: nil)
      attributes = { locale: locale }
      attributes[:description] = description if description
      attributes[:keywords] = keywords if keywords
      attributes[:whatsNew] = whats_new if whats_new
      attributes[:marketingUrl] = marketing_url if marketing_url
      attributes[:promotionalText] = promotional_text if promotional_text
      attributes[:supportUrl] = support_url if support_url

      payload = {
        data: {
          type: "appStoreVersionLocalizations",
          attributes: attributes,
          relationships: {
            appStoreVersion: {
              data: {
                type: "appStoreVersions",
                id: version_id
              }
            }
          }
        }
      }
      @client.post("appStoreVersionLocalizations", json: payload)
    end

    # Get existing localizations for a version
    # @param version_id [String] App Store version ID from Apple
    # @return [Array<Hash>] Localizations
    def localizations(version_id:)
      response = @client.get("appStoreVersions/#{version_id}/appStoreVersionLocalizations")
      response["data"] || []
    end

    # Update existing localization
    # @param localization_id [String] Localization ID from Apple
    # @param whats_new [String] What's new text
    # @param marketing_url [String] Marketing URL
    # @param promotional_text [String] Promotional text
    # @param support_url [String] Support URL
    # @return [Hash] Updated localization
    def update_localization(localization_id:, description: nil, keywords: nil, whats_new: nil, marketing_url: nil, promotional_text: nil, support_url: nil)
      attributes = {}
      attributes[:description] = description unless description.nil?
      attributes[:keywords] = keywords unless keywords.nil?
      attributes[:whatsNew] = whats_new unless whats_new.nil?
      attributes[:marketingUrl] = marketing_url unless marketing_url.nil?
      attributes[:promotionalText] = promotional_text unless promotional_text.nil?
      attributes[:supportUrl] = support_url unless support_url.nil?

      payload = {
        data: {
          type: "appStoreVersionLocalizations",
          id: localization_id,
          attributes: attributes
        }
      }
      @client.patch("appStoreVersionLocalizations/#{localization_id}", json: payload)
    end

    # Submit version for App Store review using modern reviewSubmissions API.
    #
    # Apple's one-open-submission-per-platform rule means POST /reviewSubmissions
    # returns 409 if a draft already exists for this (app, platform). We avoid
    # the conflict by first looking for an open draft via
    # {#find_open_review_submission}. If one exists we reuse it; otherwise we
    # create a new one. Either way the flow is the same after step 1:
    #
    #   Step 1 (create or reuse): POST /reviewSubmissions → submission_id
    #   Step 2 (add item):        POST /reviewSubmissionItems linking version
    #   Step 3 (submit):          PATCH /reviewSubmissions/:id submitted:true
    #
    # @param app_id [String] Apple app store ID
    # @param version_id [String] App Store version ID from Apple
    # @param platform [String] Platform (IOS, MAC_OS, TV_OS, VISION_OS)
    # @return [Hash] Structured result: { submission_id:, reused: bool, data: Hash }
    def submit_for_review(app_id:, version_id:, platform: "IOS")
      # Step 1: Find an existing open draft, or create a new submission.
      existing = find_open_review_submission(app_id: app_id, platform: platform)
      if existing
        submission_id = existing["id"]
        submission_data = existing
        reused = true
      else
        payload = {
          data: {
            type: "reviewSubmissions",
            attributes: { platform: platform },
            relationships: {
              app: { data: { type: "apps", id: app_id } }
            }
          }
        }
        submission_response = @client.post("reviewSubmissions", json: payload)
        submission_id = submission_response.dig("data", "id")
        submission_data = submission_response["data"]
        reused = false
      end

      # Step 2: Create the reviewSubmissionItem linking the version to the submission.
      # When reusing an existing draft, skip this step if the item is already attached.
      unless reused && submission_item_already_attached?(submission_id: submission_id, version_id: version_id)
        item_payload = {
          data: {
            type: "reviewSubmissionItems",
            relationships: {
              reviewSubmission: { data: { type: "reviewSubmissions", id: submission_id } },
              appStoreVersion: { data: { type: "appStoreVersions", id: version_id } }
            }
          }
        }
        @client.post("reviewSubmissionItems", json: item_payload)
      end

      # Step 3: PATCH reviewSubmissions/:id with submitted:true to actually trigger review.
      submit_payload = {
        data: {
          type: "reviewSubmissions",
          id: submission_id,
          attributes: { submitted: true }
        }
      }
      @client.patch("reviewSubmissions/#{submission_id}", json: submit_payload)

      {
        "submission_id" => submission_id,
        "reused" => reused,
        "data" => submission_data
      }
    end

    # Find an existing open reviewSubmission for the given app + platform.
    # Apple enforces one open submission per (app, platform) — we look up any
    # draft in READY_FOR_REVIEW (created but not yet submitted) and reuse it
    # rather than risking a 409 on POST /reviewSubmissions.
    #
    # @param app_id [String] Apple app store ID
    # @param platform [String] Platform (IOS, MAC_OS, TV_OS, VISION_OS)
    # @return [Hash, nil] The open submission's data hash, or nil if none exists.
    def find_open_review_submission(app_id:, platform: "IOS")
      response = @client.get("apps/#{app_id}/reviewSubmissions", params: {
        "filter[platform]" => platform,
        "filter[state]" => "READY_FOR_REVIEW",
        limit: 1
      })
      Array(response["data"]).first
    rescue StandardError => e
      Rails.logger.warn("find_open_review_submission failed: #{e.class} - #{e.message}")
      nil
    end

    # Update the release settings (releaseType + earliestReleaseDate) on an
    # existing appStoreVersion before submission. Used when the user picks
    # MANUAL or SCHEDULED on the submission form — Apple stores release_type on
    # the version itself, so we PATCH before calling submit_for_review.
    #
    # @param version_id [String] App Store version ID from Apple
    # @param release_type [String] AFTER_APPROVAL | MANUAL | SCHEDULED
    # @param earliest_release_date [Time, String, nil] Required when SCHEDULED
    # @return [Hash] Apple's response body
    def update_release_settings(version_id:, release_type:, earliest_release_date: nil)
      attributes = { releaseType: release_type }
      if release_type == "SCHEDULED" && earliest_release_date
        time = earliest_release_date.is_a?(String) ? Time.zone.parse(earliest_release_date) : earliest_release_date
        attributes[:earliestReleaseDate] = time.to_time.utc.iso8601
      end

      payload = {
        data: {
          type: "appStoreVersions",
          id: version_id,
          attributes: attributes
        }
      }
      @client.patch("appStoreVersions/#{version_id}", json: payload)
    end

    # Get version details
    # @param version_id [String] App Store version ID from Apple
    # @return [Hash] Version data
    def get(version_id:)
      response = @client.get("appStoreVersions/#{version_id}")
      response["data"]
    end

    # Delete a version (only works for PREPARE_FOR_SUBMISSION state)
    # @param version_id [String] App Store version ID from Apple
    def delete(version_id:)
      @client.delete("appStoreVersions/#{version_id}")
    end

    # Get validation errors for a version
    # @param version_id [String] App Store version ID from Apple
    # @return [Array<String>] Array of error messages
    def validation_errors(version_id:)
      # Fetch version with included relationships that might have errors
      response = @client.get("appStoreVersions/#{version_id}?include=appStoreVersionSubmission")

      errors = []

      # Check if there's a submission with errors
      submission = response.dig("included")&.find { |inc| inc["type"] == "appStoreVersionSubmissions" }
      if submission
        submission_errors = submission.dig("attributes", "errors") || []
        submission_errors.each do |error|
          errors << "#{error['code']}: #{error['detail']}"
        end
      end

      errors
    rescue => e
      [ "Unable to fetch validation errors: #{e.message}" ]
    end

    # Get phased release for a version
    # @param version_id [String] App Store version ID from Apple
    # @return [Hash, nil] Phased release data or nil if not found
    def phased_release(version_id:)
      response = @client.get("appStoreVersions/#{version_id}/appStoreVersionPhasedRelease")
      response["data"]
    rescue StandardError => e
      return nil if e.message.include?("404")
      raise
    end

    # Create a phased release for a version
    # @param version_id [String] App Store version ID from Apple
    # @param state [String] Initial phased release state (ACTIVE or INACTIVE)
    # @return [Hash] Created phased release data
    def create_phased_release(version_id:, state: "ACTIVE")
      payload = {
        data: {
          type: "appStoreVersionPhasedReleases",
          attributes: { phasedReleaseState: state },
          relationships: {
            appStoreVersion: {
              data: { type: "appStoreVersions", id: version_id }
            }
          }
        }
      }
      @client.post("appStoreVersionPhasedReleases", json: payload)
    end

    # Update an existing phased release
    # @param phased_release_id [String] Phased release ID from Apple
    # @param state [String] New phased release state
    # @return [Hash] Updated phased release data
    def update_phased_release(phased_release_id:, state:)
      payload = {
        data: {
          type: "appStoreVersionPhasedReleases",
          id: phased_release_id,
          attributes: { phasedReleaseState: state }
        }
      }
      @client.patch("appStoreVersionPhasedReleases/#{phased_release_id}", json: payload)
    end

    # Delete a phased release
    # @param phased_release_id [String] Phased release ID from Apple
    def delete_phased_release(phased_release_id:)
      @client.delete("appStoreVersionPhasedReleases/#{phased_release_id}")
    end

    # Check if a version is eligible for phased release activation
    # @param version_id [String] App Store version ID from Apple
    # @return [Symbol] Eligibility status (:can_activate, :already_active, :pending_review, :removed_from_sale, :invalid_state, :not_found)
    def phased_release_eligibility(version_id:)
      version = get(version_id: version_id)
      return :not_found unless version

      state = version.dig("attributes", "appStoreState")

      if PHASED_RELEASE_STATES[:can_activate].include?(state)
        existing = phased_release(version_id: version_id)
        existing ? :already_active : :can_activate
      elsif PHASED_RELEASE_STATES[:pending].include?(state)
        :pending_review
      elsif PHASED_RELEASE_STATES[:removed].include?(state)
        :removed_from_sale
      else
        :invalid_state
      end
    end

    private

    # Check whether a reviewSubmission already has the given version attached
    # as a reviewSubmissionItem. Used when reusing an existing draft so we
    # don't create a duplicate item. Raises on HTTP error — the caller must
    # surface the failure rather than proceed blindly (silently returning
    # false could cause a duplicate reviewSubmissionItem to be POSTed).
    def submission_item_already_attached?(submission_id:, version_id:)
      response = @client.get("reviewSubmissions/#{submission_id}/items")
      Array(response["data"]).any? do |item|
        item.dig("relationships", "appStoreVersion", "data", "id") == version_id
      end
    end
  end
end
