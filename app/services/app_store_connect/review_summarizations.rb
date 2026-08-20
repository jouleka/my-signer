module AppStoreConnect
  class ReviewSummarizations
    def initialize(client)
      @client = client
    end

    # Fetches Apple's AI-generated review summaries for an app.
    # platform: required — "IOS", "MAC_OS", "TV_OS", "VISION_OS"
    # territory: optional — ISO 3166-1 alpha-3 code (e.g., "USA")
    def list(app_id:, platform: "IOS", territory: nil, limit: 50)
      params = {
        "filter[platform]" => platform,
        "limit" => limit
      }
      params["filter[territory]"] = territory if territory

      response = @client.get("apps/#{app_id}/customerReviewSummarizations", params: params)
      response["data"] || []
    end
  end
end
