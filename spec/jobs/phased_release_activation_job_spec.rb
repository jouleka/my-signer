require "rails_helper"

RSpec.describe PhasedReleaseActivationJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }

  let!(:credential) do
    AppStoreConnectCredential.create!(
      organization: organization,
      name: "Test Credential",
      key_id: "ABC12345XY",
      issuer_id: "DEF456789-1234567890-ABC",
      private_key: "-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----",
      active: true
    )
  end

  let!(:apple_app) do
    AppleApp.create!(
      organization: organization,
      app_store_id: "123456789",
      bundle_id: "com.example.app",
      name: "Test App"
    )
  end

  let!(:app_store_version) do
    AppStoreVersion.create!(
      organization: organization,
      apple_app: apple_app,
      version_id: "v-123456",
      version_string: "1.0.0",
      platform: "IOS",
      app_store_state: "WAITING_FOR_REVIEW",
      phased_release_pending: true
    )
  end

  let(:mock_client) { instance_double(AppStoreConnect::Client) }
  let(:mock_versions_service) { instance_double(AppStoreConnect::Versions) }

  before do
    allow(AppStoreConnect::Client).to receive(:new).and_return(mock_client)
    allow(AppStoreConnect::Versions).to receive(:new).and_return(mock_versions_service)
  end

  describe "#perform" do
    it "queues the job on apple_polling queue" do
      expect {
        described_class.perform_later(app_store_version.id)
      }.to have_enqueued_job(described_class).on_queue("apple_polling")
    end

    context "when version is ready for phased release" do
      it "activates phased release and clears pending flag" do
        allow(mock_versions_service).to receive(:phased_release_eligibility)
          .with(version_id: app_store_version.version_id)
          .and_return(:can_activate)

        allow(mock_versions_service).to receive(:create_phased_release)
          .with(version_id: app_store_version.version_id, state: "ACTIVE")
          .and_return({ "data" => { "id" => "pr-123" } })

        described_class.perform_now(app_store_version.id)

        expect(app_store_version.reload.phased_release_pending).to be(false)
      end
    end

    context "when phased release is already active" do
      it "clears pending flag without error" do
        allow(mock_versions_service).to receive(:phased_release_eligibility)
          .with(version_id: app_store_version.version_id)
          .and_return(:already_active)

        described_class.perform_now(app_store_version.id)

        expect(app_store_version.reload.phased_release_pending).to be(false)
      end
    end

    context "when version is still pending review" do
      it "schedules a retry job" do
        allow(mock_versions_service).to receive(:phased_release_eligibility)
          .with(version_id: app_store_version.version_id)
          .and_return(:pending_review)

        expect {
          described_class.perform_now(app_store_version.id)
        }.to have_enqueued_job(described_class).with(app_store_version.id, hash_including(:started_at))

        expect(app_store_version.reload.phased_release_pending).to be(true)
      end

      it "uses progressively longer retry intervals" do
        allow(mock_versions_service).to receive(:phased_release_eligibility)
          .with(version_id: app_store_version.version_id)
          .and_return(:pending_review)

        # First hour: 15 minute intervals
        started_at = Time.current
        expect {
          described_class.perform_now(app_store_version.id, started_at: started_at)
        }.to have_enqueued_job(described_class)

        clear_enqueued_jobs

        # After 1 hour: 30 minute intervals - job should still be enqueued
        expect {
          described_class.perform_now(app_store_version.id, started_at: 90.minutes.ago)
        }.to have_enqueued_job(described_class)

        clear_enqueued_jobs

        # After 8 hours: 4 hour intervals - job should still be enqueued
        expect {
          described_class.perform_now(app_store_version.id, started_at: 10.hours.ago)
        }.to have_enqueued_job(described_class)
      end
    end

    context "when version is removed from sale" do
      it "gives up and clears pending flag" do
        allow(mock_versions_service).to receive(:phased_release_eligibility)
          .with(version_id: app_store_version.version_id)
          .and_return(:removed_from_sale)

        described_class.perform_now(app_store_version.id)

        expect(app_store_version.reload.phased_release_pending).to be(false)
      end
    end

    context "when version is in invalid state" do
      it "gives up and clears pending flag" do
        allow(mock_versions_service).to receive(:phased_release_eligibility)
          .with(version_id: app_store_version.version_id)
          .and_return(:invalid_state)

        described_class.perform_now(app_store_version.id)

        expect(app_store_version.reload.phased_release_pending).to be(false)
      end
    end

    context "when max retry time exceeded" do
      it "gives up after MAX_RETRY_HOURS" do
        started_at = (described_class::MAX_RETRY_HOURS + 1).hours.ago

        described_class.perform_now(app_store_version.id, started_at: started_at)

        expect(app_store_version.reload.phased_release_pending).to be(false)
      end
    end

    context "when version is deleted" do
      it "handles gracefully" do
        version_id = app_store_version.id
        app_store_version.destroy!

        expect {
          described_class.perform_now(version_id)
        }.not_to raise_error
      end
    end

    context "when version no longer has pending flag" do
      it "skips processing" do
        app_store_version.update!(phased_release_pending: false)

        expect(mock_versions_service).not_to receive(:phased_release_eligibility)

        described_class.perform_now(app_store_version.id)
      end
    end

    context "when no active credential" do
      before do
        credential.update!(active: false)
      end

      it "clears pending flag and logs warning" do
        allow(Rails.logger).to receive(:warn)

        described_class.perform_now(app_store_version.id)

        expect(app_store_version.reload.phased_release_pending).to be(false)
        expect(Rails.logger).to have_received(:warn).with(a_string_matching(/No active credential/))
      end
    end
  end
end
