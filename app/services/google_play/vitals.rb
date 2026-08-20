require "stringio"
require "googleauth"
require "google/apis/playdeveloperreporting_v1beta1"

module GooglePlay
  class Vitals
    SCOPE = "https://www.googleapis.com/auth/playdeveloperreporting".freeze
    Reporting = Google::Apis::PlaydeveloperreportingV1beta1

    def initialize(credential:, timeout: 30)
      @credential = credential
      @service = Reporting::PlaydeveloperreportingService.new
      @service.authorization = build_authorization
      @service.client_options.open_timeout_sec = timeout
      @service.client_options.read_timeout_sec = timeout
    end

    attr_reader :service

    # Fetches daily crash rate data for the last N days.
    def crash_rate(package_name:, days: 30)
      end_date = Date.current
      start_date = end_date - days

      request = build_crash_query_request(start_date, end_date,
        metrics: [ "crashRate", "distinctUsers" ])
      response = @service.query_vital_crashrate(
        "apps/#{package_name}/crashRateMetricSet", request
      )
      parse_rows(response)
    end

    # Fetches daily ANR rate data for the last N days.
    def anr_rate(package_name:, days: 30)
      end_date = Date.current
      start_date = end_date - days

      request = build_anr_query_request(start_date, end_date,
        metrics: [ "anrRate", "distinctUsers" ])
      response = @service.query_vital_anrrate(
        "apps/#{package_name}/anrRateMetricSet", request
      )
      parse_rows(response)
    end

    # Lists detected quality anomalies for an app.
    # Google auto-detects spikes in crash rate, ANR rate, etc.
    def anomalies(package_name:)
      response = @service.list_anomalies("apps/#{package_name}")
      return [] unless response&.anomalies

      response.anomalies.map do |anomaly|
        {
          id: anomaly.name,
          metric_set: anomaly.metric_set,
          dimensions: anomaly.dimensions&.map { |d| { dimension: d.dimension, value: d.string_value || d.int64_value } },
          timeline_spec: {
            start: anomaly.timeline_spec&.start_time,
            end: anomaly.timeline_spec&.end_time
          }
        }
      end
    rescue Google::Apis::ClientError => e
      Rails.logger.warn("GooglePlay::Vitals#anomalies failed: #{e.message}")
      []
    end

    private

    def build_crash_query_request(start_date, end_date, metrics:)
      Reporting::GooglePlayDeveloperReportingV1beta1QueryCrashRateMetricSetRequest.new(
        timeline_spec: build_timeline_spec(start_date, end_date),
        dimensions: [],
        metrics: metrics,
        user_cohort: "OS_PUBLIC",
        page_size: 100
      )
    end

    def build_anr_query_request(start_date, end_date, metrics:)
      Reporting::GooglePlayDeveloperReportingV1beta1QueryAnrRateMetricSetRequest.new(
        timeline_spec: build_timeline_spec(start_date, end_date),
        dimensions: [],
        metrics: metrics,
        user_cohort: "OS_PUBLIC",
        page_size: 100
      )
    end

    def build_timeline_spec(start_date, end_date)
      Reporting::GooglePlayDeveloperReportingV1beta1TimelineSpec.new(
        aggregation_period: "DAILY",
        start_time: date_to_datetime(start_date),
        end_time: date_to_datetime(end_date)
      )
    end

    def date_to_datetime(date)
      Reporting::GoogleTypeDateTime.new(
        year: date.year, month: date.month, day: date.day,
        time_zone: Reporting::GoogleTypeTimeZone.new(
          id: "America/Los_Angeles"
        )
      )
    end

    def parse_rows(response)
      return [] unless response&.rows

      response.rows.map do |row|
        date = if row.start_time
          Date.new(row.start_time.year, row.start_time.month, row.start_time.day)
        end

        metrics_hash = {}
        row.metrics&.each do |m|
          key = m.metric.underscore.to_sym
          metrics_hash[key] = m.decimal_value
        end

        { date: date, **metrics_hash }
      end
    end

    def build_authorization
      json = @credential.service_account_json
      raise "Missing service_account_json" if json.to_s.strip.empty?
      Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(json),
        scope: SCOPE
      )
    end
  end
end
