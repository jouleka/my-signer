require "rails_helper"

RSpec.describe GooglePlay::AnomalyNotifier do
  let(:organization) { create(:organization) }
  let(:android_app) { create(:android_app, organization: organization) }

  describe "#check_and_notify" do
    it "creates notifications for detected anomalies" do
      mock_vitals = instance_double(GooglePlay::Vitals)
      allow(mock_vitals).to receive(:anomalies).and_return([
        { id: "anomaly-1", metric_set: "apps/com.test/crashRateMetricSet", dimensions: [], timeline_spec: {} }
      ])

      notifier = described_class.new(organization: organization, android_app: android_app)
      # Should not raise even without admin memberships
      expect { notifier.check_and_notify(mock_vitals) }.not_to raise_error
    end

    it "does nothing when no anomalies" do
      mock_vitals = instance_double(GooglePlay::Vitals)
      allow(mock_vitals).to receive(:anomalies).and_return([])

      notifier = described_class.new(organization: organization, android_app: android_app)
      expect { notifier.check_and_notify(mock_vitals) }.not_to raise_error
    end
  end
end
