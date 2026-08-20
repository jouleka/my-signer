module AppStoreConnect
  class CustomProductPages
    def initialize(client)
      @client = client
    end

    # ─── CPP CRUD ───────────────────────────────────────────────────────

    def list(app_id:, &block)
      @client.paginate(
        "apps/#{app_id}/appCustomProductPages",
        params: { "fields[appCustomProductPages]" => "name,url,visible" },
        &block
      )
    end

    # Apple requires inline creation of version + localization in the same
    # request using JSON:API temporary IDs in the `included` array.
    # See: WWDC 2020 "Expanding automation with the App Store Connect API"
    def create(app_id:, name:, locale:, app_store_version_id: nil, promotional_text: nil)
      relationships = {
        app: { data: { type: "apps", id: app_id } },
        appCustomProductPageVersions: {
          data: [ { type: "appCustomProductPageVersions", id: "${version-1}" } ]
        }
      }

      # Copy screenshots from an existing version (optional but recommended)
      if app_store_version_id
        relationships[:appStoreVersionTemplate] = {
          data: { type: "appStoreVersions", id: app_store_version_id }
        }
      end

      version_localizations = {
        appCustomProductPageLocalizations: {
          data: [ { type: "appCustomProductPageLocalizations", id: "${locale-1}" } ]
        }
      }

      localization_attrs = { locale: locale }
      localization_attrs[:promotionalText] = promotional_text if promotional_text.present?

      payload = {
        data: {
          type: "appCustomProductPages",
          attributes: { name: name },
          relationships: relationships
        },
        included: [
          {
            type: "appCustomProductPageVersions",
            id: "${version-1}",
            relationships: version_localizations
          },
          {
            type: "appCustomProductPageLocalizations",
            id: "${locale-1}",
            attributes: localization_attrs
          }
        ]
      }
      @client.post("appCustomProductPages", json: payload)
    end

    def update(cpp_id:, name: nil, visible: nil)
      attrs = {}
      attrs[:name] = name unless name.nil?
      attrs[:visible] = visible unless visible.nil?
      payload = {
        data: {
          type: "appCustomProductPages",
          id: cpp_id,
          attributes: attrs
        }
      }
      @client.patch("appCustomProductPages/#{cpp_id}", json: payload)
    end

    def delete(cpp_id:)
      @client.delete("appCustomProductPages/#{cpp_id}")
    end

    # ─── Review Submission (3-step unified flow) ──────────────────────

    # Submit a CPP version for App Review using Apple's unified
    # reviewSubmissions API. Three sequential calls:
    #   1. Create a ReviewSubmission for the app
    #   2. Add the CPP version as a ReviewSubmissionItem
    #   3. Mark the submission as submitted
    def submit_for_review(app_id:, cpp_version_id:)
      # Step 1: Create review submission
      submission_response = @client.post("reviewSubmissions", json: {
        data: {
          type: "reviewSubmissions",
          attributes: { platform: "IOS" },
          relationships: {
            app: { data: { type: "apps", id: app_id } }
          }
        }
      })
      submission_id = submission_response.dig("data", "id")

      # Step 2: Add CPP version as review item
      @client.post("reviewSubmissionItems", json: {
        data: {
          type: "reviewSubmissionItems",
          relationships: {
            reviewSubmission: { data: { type: "reviewSubmissions", id: submission_id } },
            appCustomProductPageVersion: { data: { type: "appCustomProductPageVersions", id: cpp_version_id } }
          }
        }
      })

      # Step 3: Submit for review
      @client.patch("reviewSubmissions/#{submission_id}", json: {
        data: {
          type: "reviewSubmissions",
          id: submission_id,
          attributes: { submitted: true }
        }
      })
    end

    # ─── Versions ───────────────────────────────────────────────────────

    def versions(cpp_id:)
      @client.get("appCustomProductPages/#{cpp_id}/appCustomProductPageVersions")
    end

    # ─── Localizations ──────────────────────────────────────────────────

    def localizations(version_id:)
      @client.get("appCustomProductPageVersions/#{version_id}/appCustomProductPageLocalizations")
    end

    def create_localization(version_id:, locale:, promotional_text: nil)
      attrs = { locale: locale }
      attrs[:promotionalText] = promotional_text if promotional_text.present?
      payload = {
        data: {
          type: "appCustomProductPageLocalizations",
          attributes: attrs,
          relationships: {
            appCustomProductPageVersion: {
              data: { type: "appCustomProductPageVersions", id: version_id }
            }
          }
        }
      }
      @client.post("appCustomProductPageLocalizations", json: payload)
    end

    def update_localization(localization_id:, promotional_text:)
      payload = {
        data: {
          type: "appCustomProductPageLocalizations",
          id: localization_id,
          attributes: { promotionalText: promotional_text }
        }
      }
      @client.patch("appCustomProductPageLocalizations/#{localization_id}", json: payload)
    end

    def update_version(version_id:, deep_link: nil)
      attrs = {}
      attrs[:deepLink] = deep_link unless deep_link.nil?
      payload = {
        data: {
          type: "appCustomProductPageVersions",
          id: version_id,
          attributes: attrs
        }
      }
      @client.patch("appCustomProductPageVersions/#{version_id}", json: payload)
    end

    # ─── Screenshot Sets ────────────────────────────────────────────────

    def screenshot_sets(localization_id:)
      @client.get("appCustomProductPageLocalizations/#{localization_id}/appScreenshotSets")
    end

    # ─── Keywords (WWDC25) ──────────────────────────────────────────────
    # Keywords are `appKeywords` resources managed by Apple from your app's
    # keyword field. They're linked to CPP localizations via the
    # `relationships/searchKeywords` endpoint — NOT a standalone resource.

    # Fetch all available keywords for an app (from the keyword field)
    def available_keywords(app_id:, locale: nil)
      params = {}
      params["filter[locale]"] = locale if locale.present?
      response = @client.get("apps/#{app_id}/searchKeywords", params: params)
      response["data"] || []
    end

    # Fetch keywords currently assigned to a CPP localization
    def keywords(localization_id:)
      response = @client.get("appCustomProductPageLocalizations/#{localization_id}/searchKeywords")
      response["data"] || []
    end

    # Assign keyword(s) to a CPP localization by keyword ID
    def add_keywords(localization_id:, keyword_ids:)
      payload = {
        data: Array(keyword_ids).map { |id| { type: "appKeywords", id: id } }
      }
      @client.post(
        "appCustomProductPageLocalizations/#{localization_id}/relationships/searchKeywords",
        json: payload
      )
    end

    # Remove keyword(s) from a CPP localization by keyword ID
    def remove_keywords(localization_id:, keyword_ids:)
      payload = {
        data: Array(keyword_ids).map { |id| { type: "appKeywords", id: id } }
      }
      @client.delete_with_body(
        "appCustomProductPageLocalizations/#{localization_id}/relationships/searchKeywords",
        json: payload
      )
    end
  end
end
