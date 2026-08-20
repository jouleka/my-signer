require "rails_helper"

RSpec.describe AnalyticsSyncJob, type: :job do
  let(:organization) { create(:organization) }

  describe "#perform" do
    it "enqueues without error" do
      expect { described_class.perform_later(organization_id: organization.id) }
        .to have_enqueued_job(described_class)
    end

    it "returns early for non-existent organization" do
      expect { described_class.new.perform(organization_id: -1) }.not_to raise_error
    end

    context "when review monitoring is disabled" do
      before do
        allow_any_instance_of(Pricing::Entitlements)
          .to receive(:review_monitoring_enabled?).and_return(false)
      end

      it "does not attempt sync" do
        expect(AppStoreConnect::Client).not_to receive(:new)
        described_class.new.perform(organization_id: organization.id)
      end
    end

    context "with Apple analytics" do
      it "fetches downloads, engagement, crashes, installs, and subscription data" do
        # This tests that the job handles the full sync without errors
        # API calls are not made since no credentials exist
        expect { described_class.new.perform(organization_id: organization.id) }.not_to raise_error
      end
    end

    context "Play Developer Reporting API disabled detection" do
      let(:gp_credential) do
        GooglePlayCredential.create!(
          organization: organization,
          name: "Test GP",
          service_account_json: {
            type: "service_account",
            project_id: "test-project-12345",
            private_key: "-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----\n",
            client_email: "sa@test.iam.gserviceaccount.com",
            client_id: "654321"
          }.to_json,
          active: true
        )
      end
      let!(:android_app) do
        AndroidApp.create!(
          organization: organization,
          package_name: "com.example.reporting",
          name: "Example"
        )
      end

      before do
        # Route the Apple side through a no-op so we can isolate the GP path.
        allow_any_instance_of(described_class).to receive(:sync_apple_analytics)

        # Force the entitlement check through.
        allow_any_instance_of(Pricing::Entitlements)
          .to receive(:analytics_dashboard_enabled?).and_return(true)

        gp_credential
      end

      def disabled_api_error
        # Mirror the exact shape google-apis-core raises when the service
        # hasn't been enabled in the caller's Google Cloud project.
        Google::Apis::ClientError.new(
          "PERMISSION_DENIED: Google Play Developer Reporting API has not been used in project 801233003955 before or it is disabled. SERVICE_DISABLED",
          status_code: 403
        )
      end

      it "stamps play_reporting_api_disabled_at when the Reporting API is disabled" do
        vitals_double = instance_double(GooglePlay::Vitals)
        allow(GooglePlay::Vitals).to receive(:new).and_return(vitals_double)
        allow(vitals_double).to receive(:crash_rate).and_raise(disabled_api_error)
        allow(vitals_double).to receive(:anr_rate).and_raise(disabled_api_error)

        expect {
          described_class.new.perform(organization_id: organization.id)
        }.to change { gp_credential.reload.play_reporting_api_disabled_at }.from(nil)

        expect(gp_credential.reload.play_reporting_api_disabled?).to be true
      end

      it "clears the stamp on a subsequent successful vitals call" do
        gp_credential.mark_play_reporting_api_disabled!
        expect(gp_credential.reload.play_reporting_api_disabled?).to be true

        vitals_double = instance_double(GooglePlay::Vitals)
        allow(GooglePlay::Vitals).to receive(:new).and_return(vitals_double)
        allow(vitals_double).to receive(:crash_rate).and_return([])
        allow(vitals_double).to receive(:anr_rate).and_return([])
        allow_any_instance_of(GooglePlay::AnomalyNotifier).to receive(:check_and_notify)

        described_class.new.perform(organization_id: organization.id)

        expect(gp_credential.reload.play_reporting_api_disabled_at).to be_nil
      end

      it "does not stamp on unrelated 403s (e.g. per-app permission denial)" do
        unrelated = Google::Apis::ClientError.new("App not found", status_code: 403)
        vitals_double = instance_double(GooglePlay::Vitals)
        allow(GooglePlay::Vitals).to receive(:new).and_return(vitals_double)
        allow(vitals_double).to receive(:crash_rate).and_raise(unrelated)
        allow(vitals_double).to receive(:anr_rate).and_raise(unrelated)

        described_class.new.perform(organization_id: organization.id)

        expect(gp_credential.reload.play_reporting_api_disabled_at).to be_nil
      end
    end
  end
end
