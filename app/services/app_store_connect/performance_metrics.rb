module AppStoreConnect
  class PerformanceMetrics
    def initialize(client)
      @client = client
    end

    # Fetches aggregated performance/power metrics for an app.
    # Returns metrics like launch time, hang rate, memory usage, battery drain.
    def app_metrics(app_id:)
      response = @client.get("apps/#{app_id}/perfPowerMetrics", params: {
        "filter[metricType]" => "LAUNCH,HANG,MEMORY,DISK",
        "filter[platform]" => "IOS"
      })
      parse_metrics(response)
    rescue StandardError => e
      Rails.logger.warn("AppStoreConnect::PerformanceMetrics#app_metrics failed: #{e.message}")
      {}
    end

    # Fetches performance metrics for a specific build.
    def build_metrics(build_id:)
      response = @client.get("builds/#{build_id}/perfPowerMetrics", params: {
        "filter[metricType]" => "LAUNCH,HANG,MEMORY,DISK",
        "filter[platform]" => "IOS"
      })
      parse_metrics(response)
    rescue StandardError => e
      Rails.logger.warn("AppStoreConnect::PerformanceMetrics#build_metrics failed: #{e.message}")
      {}
    end

    # Fetches diagnostic signatures (grouped crash/issue patterns) for a build.
    def diagnostic_signatures(build_id:, limit: 50)
      response = @client.get("builds/#{build_id}/diagnosticSignatures", params: {
        "limit" => limit
      })
      data = response["data"] || []
      data.map do |sig|
        attrs = sig["attributes"] || {}
        {
          id: sig["id"],
          signature: attrs["signature"],
          diagnostic_type: attrs["diagnosticType"],
          weight: attrs["weight"]
        }
      end
    rescue StandardError => e
      Rails.logger.warn("AppStoreConnect::PerformanceMetrics#diagnostic_signatures failed: #{e.message}")
      []
    end

    private

    def parse_metrics(response)
      product_data = response["productData"] || response["data"] || []
      return {} if product_data.empty?

      metrics = {}
      product_data.each do |product|
        metric_data = product["metricCategories"] || product["attributes"]&.dig("metricCategories") || []
        metric_data.each do |category|
          category_id = category["identifier"] || category["metricType"]
          category_metrics = category["metrics"] || []
          category_metrics.each do |metric|
            metric_id = metric["identifier"] || metric["metricType"]
            unit = metric["unit"]
            datasets = metric["datasets"] || []
            latest = datasets.first
            points = latest&.dig("points") || []
            latest_point = points.last

            metrics["#{category_id}.#{metric_id}"] = {
              value: latest_point&.dig("value"),
              percentile: latest_point&.dig("percentileValue"),
              unit: unit,
              goal: metric["goalKeys"]&.first
            }
          end
        end
      end
      metrics
    end
  end
end
