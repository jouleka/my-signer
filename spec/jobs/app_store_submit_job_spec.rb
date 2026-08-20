require "rails_helper"

RSpec.describe AppStoreSubmitJob, type: :job do
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

  let!(:apple_app) { create(:apple_app, organization: organization, app_store_id: "999888777") }
  let!(:apple_build) { create(:apple_build, apple_app: apple_app, organization: organization) }

  let!(:version) do
    create(:app_store_version,
           apple_app: apple_app,
           organization: organization,
           version_string: "1.2.3",
           app_store_state: "PREPARE_FOR_SUBMISSION",
           apple_build: apple_build,
           submission_status: "submitting")
  end

  let(:mock_client) { instance_double(AppStoreConnect::Client) }
  let(:mock_versions_service) { instance_double(AppStoreConnect::Versions) }

  before do
    allow(AppStoreConnect::Client).to receive(:new).and_return(mock_client)
    allow(AppStoreConnect::Versions).to receive(:new).and_return(mock_versions_service)
    allow(mock_versions_service).to receive(:validation_errors).and_return([])
  end

  describe "#perform" do
    context "happy path — AFTER_APPROVAL" do
      before do
        allow(mock_versions_service).to receive(:submit_for_review)
          .with(app_id: apple_app.app_store_id, version_id: version.version_id, platform: "IOS")
          .and_return("submission_id" => "sub-1", "reused" => false, "data" => {})
      end

      it "submits the version and transitions state to WAITING_FOR_REVIEW" do
        described_class.perform_now(
          organization_id: organization.id,
          app_store_version_id: version.id
        )

        version.reload
        expect(version.app_store_state).to eq("WAITING_FOR_REVIEW")
        expect(version.submission_status).to eq("submitted")
        expect(version.submission_error).to be_nil
      end

      it "does not call update_release_settings when release_type is AFTER_APPROVAL" do
        expect(mock_versions_service).not_to receive(:update_release_settings)

        described_class.perform_now(
          organization_id: organization.id,
          app_store_version_id: version.id,
          release_type: "AFTER_APPROVAL"
        )
      end
    end

    context "with MANUAL release_type" do
      it "calls update_release_settings before submit_for_review" do
        expect(mock_versions_service).to receive(:update_release_settings)
          .with(version_id: version.version_id, release_type: "MANUAL", earliest_release_date: nil)
          .ordered

        expect(mock_versions_service).to receive(:submit_for_review)
          .with(app_id: apple_app.app_store_id, version_id: version.version_id, platform: "IOS")
          .ordered
          .and_return("submission_id" => "sub-2", "reused" => false, "data" => {})

        described_class.perform_now(
          organization_id: organization.id,
          app_store_version_id: version.id,
          release_type: "MANUAL"
        )

        expect(version.reload.submission_status).to eq("submitted")
      end
    end

    context "with SCHEDULED release_type" do
      let(:scheduled_at) { 2.days.from_now.utc.iso8601 }

      it "passes the earliest_release_date to update_release_settings" do
        expect(mock_versions_service).to receive(:update_release_settings)
          .with(version_id: version.version_id, release_type: "SCHEDULED", earliest_release_date: scheduled_at)

        expect(mock_versions_service).to receive(:submit_for_review)
          .and_return("submission_id" => "sub-3", "reused" => false, "data" => {})

        described_class.perform_now(
          organization_id: organization.id,
          app_store_version_id: version.id,
          release_type: "SCHEDULED",
          earliest_release_date: scheduled_at
        )
      end
    end

    context "when Apple rejects submission" do
      before do
        allow(mock_versions_service).to receive(:submit_for_review)
          .and_raise(StandardError, "ENTITY_ERROR: Version is not in valid state for submission")
      end

      it "records the failure on the version" do
        described_class.perform_now(
          organization_id: organization.id,
          app_store_version_id: version.id
        )

        version.reload
        expect(version.submission_status).to eq("failed")
        expect(version.submission_error).to include("first-time submissions")
        expect(version.app_store_state).to eq("PREPARE_FOR_SUBMISSION") # unchanged
      end

      it "attempts to refresh validation errors from Apple on failure" do
        expect(mock_versions_service).to receive(:validation_errors).at_least(:once)
          .with(version_id: version.version_id)
          .and_return([ "MISSING_SCREENSHOTS: iPhone 6.7\" screenshots are required" ])

        described_class.perform_now(
          organization_id: organization.id,
          app_store_version_id: version.id
        )

        expect(version.reload.issues).to be_an(Array)
        expect(version.issues.first).to include("detail")
      end
    end

    context "when no active credential" do
      before { credential.update!(active: false) }

      it "records 'no credential' failure without calling Apple" do
        expect(AppStoreConnect::Client).not_to receive(:new)

        described_class.perform_now(
          organization_id: organization.id,
          app_store_version_id: version.id
        )

        version.reload
        expect(version.submission_status).to eq("failed")
        expect(version.submission_error).to include("No active App Store Connect credential")
      end
    end

    context "when organization is deleted between enqueue and perform" do
      it "handles gracefully" do
        org_id = organization.id
        version_id = version.id
        organization.destroy!

        expect {
          described_class.perform_now(
            organization_id: org_id,
            app_store_version_id: version_id
          )
        }.not_to raise_error
      end
    end

    context "error message sanitization" do
      before do
        allow(mock_versions_service).to receive(:submit_for_review)
          .and_raise(StandardError, "Bearer sk-abc123xyz token=secret123 failed to submit")
      end

      it "redacts credentials from the stored error message" do
        described_class.perform_now(
          organization_id: organization.id,
          app_store_version_id: version.id
        )

        msg = version.reload.submission_error
        expect(msg).not_to include("sk-abc123xyz")
        expect(msg).not_to include("secret123")
        expect(msg).to include("[REDACTED]")
      end
    end
  end
end
