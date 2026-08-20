require "rails_helper"

RSpec.describe AppStoreConnect::ReviewSummarizations do
  let(:mock_client) { instance_double(AppStoreConnect::Client) }
  subject { described_class.new(mock_client) }

  describe "#list" do
    let(:api_response) do
      {
        "data" => [
          {
            "type" => "customerReviewSummarizations",
            "id" => "sum-1",
            "attributes" => {
              "text" => "Users love the clean design but report occasional crashes.",
              "locale" => "en-US",
              "platform" => "IOS",
              "createdDate" => "2026-04-10T00:00:00Z"
            }
          }
        ]
      }
    end

    it "fetches summarizations for an app with platform filter" do
      expect(mock_client).to receive(:get)
        .with("apps/123/customerReviewSummarizations", params: {
          "filter[platform]" => "IOS",
          "limit" => 50
        })
        .and_return(api_response)

      result = subject.list(app_id: "123", platform: "IOS")
      expect(result).to be_an(Array)
      expect(result.size).to eq(1)
      expect(result.first.dig("attributes", "text")).to include("clean design")
    end

    it "returns empty array when no summarizations exist" do
      expect(mock_client).to receive(:get).and_return({ "data" => [] })
      result = subject.list(app_id: "123", platform: "IOS")
      expect(result).to eq([])
    end

    it "includes territory filter when provided" do
      expect(mock_client).to receive(:get)
        .with("apps/123/customerReviewSummarizations", params: {
          "filter[platform]" => "IOS",
          "filter[territory]" => "USA",
          "limit" => 50
        })
        .and_return({ "data" => [] })

      subject.list(app_id: "123", territory: "USA")
    end
  end
end
