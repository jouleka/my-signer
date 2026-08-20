require "rails_helper"

RSpec.describe AppStoreConnect::PerformanceMetrics do
  let(:mock_client) { instance_double(AppStoreConnect::Client) }
  subject { described_class.new(mock_client) }

  describe "#app_metrics" do
    it "fetches and parses performance metrics" do
      allow(mock_client).to receive(:get).and_return({
        "productData" => [ {
          "metricCategories" => [ {
            "identifier" => "LAUNCH",
            "metrics" => [ {
              "identifier" => "launchTime",
              "unit" => "ms",
              "datasets" => [ { "points" => [ { "value" => 850 } ] } ]
            } ]
          } ]
        } ]
      })

      result = subject.app_metrics(app_id: "123")
      expect(result["LAUNCH.launchTime"][:value]).to eq(850)
    end

    it "returns empty hash on API error" do
      allow(mock_client).to receive(:get).and_raise(StandardError, "timeout")
      result = subject.app_metrics(app_id: "123")
      expect(result).to eq({})
    end
  end

  describe "#diagnostic_signatures" do
    it "fetches crash signatures for a build" do
      allow(mock_client).to receive(:get).and_return({
        "data" => [ {
          "id" => "sig-1",
          "attributes" => {
            "signature" => "EXC_BAD_ACCESS KERN_INVALID_ADDRESS",
            "diagnosticType" => "CRASH",
            "weight" => 0.45
          }
        } ]
      })

      result = subject.diagnostic_signatures(build_id: "build-1")
      expect(result.size).to eq(1)
      expect(result.first[:diagnostic_type]).to eq("CRASH")
    end
  end
end
