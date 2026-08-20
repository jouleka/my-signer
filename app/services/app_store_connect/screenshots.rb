module AppStoreConnect
  class Screenshots
    # Map resolution to App Store Connect display type
    DISPLAY_TYPES = {
      "1320x2868" => "APP_IPHONE_67",
      "1290x2796" => "APP_IPHONE_67",
      "1242x2688" => "APP_IPHONE_65",
      "1242x2208" => "APP_IPHONE_55",
      "2048x2732" => "APP_IPAD_PRO_3GEN_129",
      "1668x2388" => "APP_IPAD_PRO_3GEN_11"
    }.freeze

    def initialize(client)
      @client = client
    end

    def create_screenshot_set(localization_id:, display_type:, localization_type: :app_store_version)
      if localization_type == :custom_product_page
        relationship_key = :appCustomProductPageLocalization
        relationship_type = "appCustomProductPageLocalizations"
      else
        relationship_key = :appStoreVersionLocalization
        relationship_type = "appStoreVersionLocalizations"
      end

      payload = {
        data: {
          type: "appScreenshotSets",
          attributes: { screenshotDisplayType: display_type },
          relationships: {
            relationship_key => {
              data: { type: relationship_type, id: localization_id }
            }
          }
        }
      }
      @client.post("appScreenshotSets", json: payload)
    end

    def list_cpp_screenshot_sets(localization_id:)
      response = @client.get("appCustomProductPageLocalizations/#{localization_id}/appScreenshotSets")
      response["data"] || []
    end

    def list_screenshot_sets(localization_id:)
      response = @client.get("appStoreVersionLocalizations/#{localization_id}/appScreenshotSets")
      response["data"] || []
    end

    def list_screenshots(set_id:)
      response = @client.get("appScreenshotSets/#{set_id}/appScreenshots")
      response["data"] || []
    end

    def delete_screenshot(id:)
      @client.delete("appScreenshots/#{id}")
    end

    # Deletes an entire screenshot set AND all its screenshots in one API call.
    # Far more efficient than listing + deleting individual screenshots.
    def delete_screenshot_set(id:)
      @client.delete("appScreenshotSets/#{id}")
    end

    # Multi-step upload flow:
    # 1. Reserve upload slot (POST appScreenshots)
    # 2. PUT binary data to Apple CDN URL
    # 3. Commit with checksum (PATCH appScreenshots)
    def upload_screenshot!(set_id:, file_path:)
      file_data = File.binread(file_path)
      file_name = File.basename(file_path)
      file_size = file_data.bytesize
      checksum = Digest::MD5.base64digest(file_data)

      # Step 1: Reserve upload
      reserve_payload = {
        data: {
          type: "appScreenshots",
          attributes: {
            fileName: file_name,
            fileSize: file_size
          },
          relationships: {
            appScreenshotSet: {
              data: { type: "appScreenshotSets", id: set_id }
            }
          }
        }
      }
      reserve_response = @client.post("appScreenshots", json: reserve_payload)
      screenshot_id = reserve_response.dig("data", "id")
      upload_operations = reserve_response.dig("data", "attributes", "uploadOperations")

      # Step 2: Upload binary chunks to Apple CDN
      upload_operations&.each do |operation|
        url = operation["url"]
        offset = operation["offset"]
        length = operation["length"]
        request_headers = (operation["requestHeaders"] || []).each_with_object({}) do |h, memo|
          memo[h["name"]] = h["value"]
        end

        chunk = file_data[offset, length]
        @client.put_binary(url: url, data: chunk, content_type: "application/octet-stream", headers: request_headers)
      end

      # Step 3: Commit with checksum
      commit_payload = {
        data: {
          type: "appScreenshots",
          id: screenshot_id,
          attributes: {
            uploaded: true,
            sourceFileChecksum: checksum
          }
        }
      }
      @client.patch("appScreenshots/#{screenshot_id}", json: commit_payload)
    end

    def display_type_for_resolution(width, height)
      DISPLAY_TYPES["#{width}x#{height}"]
    end
  end
end
