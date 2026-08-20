require "rails_helper"

RSpec.describe AppStoreConnect::Screenshots do
  let(:mock_client) { instance_double(AppStoreConnect::Client) }
  let(:service) { described_class.new(mock_client) }

  describe "DISPLAY_TYPES" do
    it "maps iPhone 6.9\" resolution" do
      expect(described_class::DISPLAY_TYPES["1320x2868"]).to eq("APP_IPHONE_67")
    end

    it "maps iPhone 6.7\" resolution" do
      expect(described_class::DISPLAY_TYPES["1290x2796"]).to eq("APP_IPHONE_67")
    end

    it "maps iPhone 6.5\" resolution" do
      expect(described_class::DISPLAY_TYPES["1242x2688"]).to eq("APP_IPHONE_65")
    end

    it "maps iPhone 5.5\" resolution" do
      expect(described_class::DISPLAY_TYPES["1242x2208"]).to eq("APP_IPHONE_55")
    end

    it "maps iPad 12.9\" resolution" do
      expect(described_class::DISPLAY_TYPES["2048x2732"]).to eq("APP_IPAD_PRO_3GEN_129")
    end

    it "maps iPad 11\" resolution" do
      expect(described_class::DISPLAY_TYPES["1668x2388"]).to eq("APP_IPAD_PRO_3GEN_11")
    end
  end

  describe "#display_type_for_resolution" do
    it "returns display type for known resolution" do
      expect(service.display_type_for_resolution(1320, 2868)).to eq("APP_IPHONE_67")
    end

    it "returns nil for unknown resolution" do
      expect(service.display_type_for_resolution(999, 999)).to be_nil
    end
  end

  describe "#create_screenshot_set" do
    it "sends correct payload to Apple" do
      expected_payload = {
        data: {
          type: "appScreenshotSets",
          attributes: { screenshotDisplayType: "APP_IPHONE_67" },
          relationships: {
            appStoreVersionLocalization: {
              data: { type: "appStoreVersionLocalizations", id: "loc-123" }
            }
          }
        }
      }

      expect(mock_client).to receive(:post).with("appScreenshotSets", json: expected_payload)
        .and_return({ "data" => { "id" => "set-123" } })

      service.create_screenshot_set(localization_id: "loc-123", display_type: "APP_IPHONE_67")
    end
  end

  describe "#list_screenshot_sets" do
    it "returns screenshot sets for a localization" do
      expect(mock_client).to receive(:get)
        .with("appStoreVersionLocalizations/loc-123/appScreenshotSets")
        .and_return({ "data" => [ { "id" => "set-1" }, { "id" => "set-2" } ] })

      result = service.list_screenshot_sets(localization_id: "loc-123")
      expect(result.length).to eq(2)
    end

    it "returns empty array when no data" do
      expect(mock_client).to receive(:get)
        .with("appStoreVersionLocalizations/loc-123/appScreenshotSets")
        .and_return({})

      result = service.list_screenshot_sets(localization_id: "loc-123")
      expect(result).to eq([])
    end
  end

  describe "#list_screenshots" do
    it "returns screenshots for a set" do
      expect(mock_client).to receive(:get)
        .with("appScreenshotSets/set-123/appScreenshots")
        .and_return({ "data" => [ { "id" => "ss-1" } ] })

      result = service.list_screenshots(set_id: "set-123")
      expect(result.length).to eq(1)
    end
  end

  describe "#delete_screenshot" do
    it "deletes a screenshot" do
      expect(mock_client).to receive(:delete).with("appScreenshots/ss-123")

      service.delete_screenshot(id: "ss-123")
    end
  end

  describe "#upload_screenshot!" do
    let(:tmp_file) { Tempfile.new([ "test_screenshot", ".png" ]) }

    before do
      tmp_file.write("fake_png_data")
      tmp_file.rewind
    end

    after do
      tmp_file.close
      tmp_file.unlink
    end

    it "performs the 3-step upload flow" do
      # Step 1: Reserve
      reserve_response = {
        "data" => {
          "id" => "ss-new",
          "attributes" => {
            "uploadOperations" => [
              {
                "url" => "https://cdn.apple.com/upload",
                "offset" => 0,
                "length" => 13,
                "requestHeaders" => [ { "name" => "x-apple-header", "value" => "value" } ]
              }
            ]
          }
        }
      }

      expect(mock_client).to receive(:post).with("appScreenshots", json: hash_including(:data))
        .and_return(reserve_response)

      # Step 2: Binary upload
      expect(mock_client).to receive(:put_binary).with(
        url: "https://cdn.apple.com/upload",
        data: "fake_png_data",
        content_type: "application/octet-stream",
        headers: { "x-apple-header" => "value" }
      )

      # Step 3: Commit
      expect(mock_client).to receive(:patch).with("appScreenshots/ss-new", json: hash_including(:data))

      service.upload_screenshot!(set_id: "set-123", file_path: tmp_file.path)
    end
  end
end
