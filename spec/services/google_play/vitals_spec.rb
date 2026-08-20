require "rails_helper"

RSpec.describe GooglePlay::Vitals do
  # We need to stub the entire initialization since it tries to auth
  let(:credential) do
    double("Credential",
      service_account_json: {
        type: "service_account",
        project_id: "test",
        private_key_id: "key",
        private_key: SpecCredentialFixtures.pem(label: "RSA PRIVATE KEY"),
        client_email: "test@test.iam.gserviceaccount.com",
        client_id: "123",
        auth_uri: "https://accounts.google.com/o/oauth2/auth",
        token_uri: "https://oauth2.googleapis.com/token"
      }.to_json,
      active?: true
    )
  end

  describe "#crash_rate" do
    it "returns parsed crash rate data" do
      vitals = described_class.allocate
      mock_service = instance_double(
        Google::Apis::PlaydeveloperreportingV1beta1::PlaydeveloperreportingService
      )
      vitals.instance_variable_set(:@service, mock_service)
      vitals.instance_variable_set(:@credential, credential)

      # Build mock response
      mock_metric_crash = double("Metric", metric: "crashRate", decimal_value: "0.0023")
      mock_metric_users = double("Metric", metric: "distinctUsers", decimal_value: "15000")
      mock_row = double("Row",
        start_time: double("DateTime", year: 2026, month: 4, day: 10),
        metrics: [ mock_metric_crash, mock_metric_users ],
        dimensions: []
      )
      mock_response = double("Response", rows: [ mock_row ], next_page_token: nil)

      allow(mock_service).to receive(:query_vital_crashrate).and_return(mock_response)

      result = vitals.crash_rate(package_name: "com.example.app", days: 30)
      expect(result).to be_an(Array)
      expect(result.size).to eq(1)
      expect(result.first[:date]).to eq(Date.new(2026, 4, 10))
      expect(result.first[:crash_rate]).to eq("0.0023")
      expect(result.first[:distinct_users]).to eq("15000")
    end
  end

  describe "#anr_rate" do
    it "returns parsed ANR rate data" do
      vitals = described_class.allocate
      mock_service = instance_double(
        Google::Apis::PlaydeveloperreportingV1beta1::PlaydeveloperreportingService
      )
      vitals.instance_variable_set(:@service, mock_service)
      vitals.instance_variable_set(:@credential, credential)

      mock_metric = double("Metric", metric: "anrRate", decimal_value: "0.0015")
      mock_row = double("Row",
        start_time: double("DateTime", year: 2026, month: 4, day: 10),
        metrics: [ mock_metric ],
        dimensions: []
      )
      mock_response = double("Response", rows: [ mock_row ])

      allow(mock_service).to receive(:query_vital_anrrate).and_return(mock_response)

      result = vitals.anr_rate(package_name: "com.example.app", days: 30)
      expect(result.first[:anr_rate]).to eq("0.0015")
    end
  end

  describe "#parse_rows with empty response" do
    it "returns empty array for nil rows" do
      vitals = described_class.allocate
      result = vitals.send(:parse_rows, double("Response", rows: nil))
      expect(result).to eq([])
    end
  end
end
