require "zlib"
require "csv"
require "net/http"
require "ipaddr"
require "stringio"

module AppStoreConnect
  class AnalyticsReports
    def initialize(client)
      @client = client
    end

    # Creates or retrieves an ONGOING analytics report request for an app.
    # Returns the request ID.
    def ensure_report_request(app_id:, access_type: "ONGOING")
      existing = @client.get("apps/#{app_id}/analyticsReportRequests", params: {
        "filter[accessType]" => access_type, "limit" => 1
      })
      existing_data = existing["data"]
      return existing_data.first["id"] if existing_data&.any?

      response = @client.post("analyticsReportRequests", json: {
        data: {
          type: "analyticsReportRequests",
          attributes: { accessType: access_type },
          relationships: {
            app: { data: { type: "apps", id: app_id } }
          }
        }
      })
      response.dig("data", "id")
    end

    # Lists reports for a request, filtered by category.
    # Categories: APP_STORE_ENGAGEMENT, COMMERCE, APP_USAGE, PERFORMANCE, FRAMEWORK_USAGE
    def list_reports(request_id:, category: nil)
      params = { "limit" => 200 }
      params["filter[category]"] = category if category
      response = @client.get("analyticsReportRequests/#{request_id}/reports", params: params)
      response["data"] || []
    end

    # Gets the most recent daily instance for a report.
    def latest_instance(report_id:, granularity: "DAILY")
      response = @client.get("analyticsReports/#{report_id}/instances", params: {
        "filter[granularity]" => granularity,
        "limit" => 1
      })
      data = response["data"] || []
      data.first
    end

    # Downloads a report segment, decompresses, and parses TSV into array of hashes.
    def download_segment(instance_id:)
      segments = @client.get("analyticsReportInstances/#{instance_id}/segments", params: {
        "limit" => 10
      })
      segment_data = segments["data"] || []
      return [] if segment_data.empty?

      url = segment_data.first.dig("attributes", "url")
      return [] unless url

      uri = URI.parse(url)
      validate_download_url!(uri)
      response = Net::HTTP.get_response(uri)
      raise "Download failed: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      decompressed = Zlib::GzipReader.new(StringIO.new(response.body)).read
      CSV.parse(decompressed, col_sep: "\t", headers: true).map(&:to_h)
    rescue Zlib::GzipFile::Error
      CSV.parse(response.body, col_sep: "\t", headers: true).map(&:to_h)
    end

    private

    # Validates that a download URL is safe to request (HTTPS, no private IPs).
    # Prevents SSRF if an API response contains a tampered URL.
    def validate_download_url!(uri)
      raise "Unsafe URL scheme: #{uri.scheme}" unless uri.scheme == "https"

      begin
        addrs = Addrinfo.getaddrinfo(uri.host, nil, :UNSPEC, :STREAM)
        addrs.each do |addr|
          ip = IPAddr.new(addr.ip_address)
          if ip.loopback? || ip.private? || ip.link_local?
            raise "Unsafe URL target: #{uri.host} resolves to private address"
          end
        end
      rescue SocketError
        raise "Cannot resolve host: #{uri.host}"
      end
    end

    public

    # High-level: fetch latest data for a specific report by name and category.
    def fetch_latest_report_data(app_id:, category:, report_name:)
      request_id = ensure_report_request(app_id: app_id)
      reports = list_reports(request_id: request_id, category: category)
      report = reports.find { |r| r.dig("attributes", "name")&.include?(report_name) }
      return [] unless report

      instance = latest_instance(report_id: report["id"])
      return [] unless instance

      download_segment(instance_id: instance["id"])
    end
  end
end
