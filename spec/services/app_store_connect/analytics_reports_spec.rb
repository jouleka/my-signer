require "rails_helper"
require "webmock/rspec"

RSpec.describe AppStoreConnect::AnalyticsReports do
  let(:mock_client) { instance_double(AppStoreConnect::Client) }
  subject { described_class.new(mock_client) }

  describe "#ensure_report_request" do
    it "returns existing request ID if one exists" do
      expect(mock_client).to receive(:get)
        .with("apps/app-123/analyticsReportRequests", params: {
          "filter[accessType]" => "ONGOING", "limit" => 1
        })
        .and_return({ "data" => [ { "id" => "req-existing" } ] })

      result = subject.ensure_report_request(app_id: "app-123")
      expect(result).to eq("req-existing")
    end

    it "creates a new request if none exists" do
      expect(mock_client).to receive(:get)
        .and_return({ "data" => [] })
      expect(mock_client).to receive(:post)
        .with("analyticsReportRequests", json: {
          data: {
            type: "analyticsReportRequests",
            attributes: { accessType: "ONGOING" },
            relationships: {
              app: { data: { type: "apps", id: "app-123" } }
            }
          }
        })
        .and_return({ "data" => { "id" => "req-new" } })

      result = subject.ensure_report_request(app_id: "app-123")
      expect(result).to eq("req-new")
    end
  end

  describe "#list_reports" do
    it "fetches reports filtered by category" do
      expect(mock_client).to receive(:get)
        .with("analyticsReportRequests/req-1/reports", params: {
          "filter[category]" => "APP_STORE_ENGAGEMENT",
          "limit" => 200
        })
        .and_return({ "data" => [ { "id" => "r-1", "attributes" => { "name" => "App Store Discovery" } } ] })

      result = subject.list_reports(request_id: "req-1", category: "APP_STORE_ENGAGEMENT")
      expect(result.size).to eq(1)
    end
  end

  describe "#latest_instance" do
    it "fetches the most recent daily instance" do
      expect(mock_client).to receive(:get)
        .with("analyticsReports/r-1/instances", params: {
          "filter[granularity]" => "DAILY",
          "limit" => 1
        })
        .and_return({ "data" => [ { "id" => "inst-1", "attributes" => { "processingDate" => "2026-04-10" } } ] })

      result = subject.latest_instance(report_id: "r-1")
      expect(result["id"]).to eq("inst-1")
    end

    it "returns nil when no instances exist" do
      expect(mock_client).to receive(:get)
        .and_return({ "data" => [] })
      result = subject.latest_instance(report_id: "r-1")
      expect(result).to be_nil
    end
  end

  describe "#download_segment" do
    it "downloads and parses gzipped TSV data" do
      expect(mock_client).to receive(:get)
        .with("analyticsReportInstances/inst-1/segments", params: { "limit" => 10 })
        .and_return({ "data" => [ { "attributes" => { "url" => "https://example.com/report.txt.gz" } } ] })

      gzipped = StringIO.new
      gz = Zlib::GzipWriter.new(gzipped)
      gz.write("Date\tFirst-Time Downloads\tRedownloads\n2026-04-10\t93\t55\n")
      gz.close

      stub_request(:get, "https://example.com/report.txt.gz")
        .to_return(body: gzipped.string)

      rows = subject.download_segment(instance_id: "inst-1")
      expect(rows.first["Date"]).to eq("2026-04-10")
      expect(rows.first["First-Time Downloads"]).to eq("93")
      expect(rows.first["Redownloads"]).to eq("55")
    end

    it "returns empty array when no segments exist" do
      expect(mock_client).to receive(:get)
        .and_return({ "data" => [] })
      result = subject.download_segment(instance_id: "inst-1")
      expect(result).to eq([])
    end
  end
end
