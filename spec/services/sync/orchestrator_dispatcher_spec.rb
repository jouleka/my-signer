require "rails_helper"
require "active_job/test_helper"

RSpec.describe Sync::OrchestratorDispatcher do
  include ActiveJob::TestHelper

  let(:organization) { create(:organization) }

  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original
  end

  before do
    # Bypass the Rails.cache burst-cooldown so successive tests don't see :cooldown.
    Rails.cache.clear
  end

  describe "#call" do
    context "when the org has no credentials and no entitlements" do
      before do
        allow_any_instance_of(Pricing::Entitlements).to receive(:review_monitoring_enabled?).and_return(false)
        allow_any_instance_of(Pricing::Entitlements).to receive(:analytics_dashboard_enabled?).and_return(false)
        allow_any_instance_of(Pricing::Entitlements).to receive(:custom_product_pages_enabled?).and_return(false)
        allow_any_instance_of(Pricing::Entitlements).to receive(:keyword_tracking_enabled?).and_return(false)
      end

      it "enqueues nothing and returns an empty hash" do
        result = described_class.new(organization: organization).call
        expect(result).to eq({})
        expect(AppStoreConnectSyncJob).not_to have_been_enqueued
        expect(GooglePlaySyncJob).not_to have_been_enqueued
        expect(ReviewSyncJob).not_to have_been_enqueued
        expect(AnalyticsSyncJob).not_to have_been_enqueued
        expect(CppSyncJob).not_to have_been_enqueued
        expect(Aso::KeywordRankCheckJob).not_to have_been_enqueued
      end
    end

    context "with ASC + GP creds and all entitlements on" do
      let!(:asc_cred) { create(:app_store_connect_credential, organization: organization, active: true) }
      let!(:gp_cred) {
      create(:google_play_credential, organization: organization, active: true,
        service_account_json: {
          type: "service_account",
          project_id: "test",
          private_key_id: "k1",
          private_key: "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n",
          client_email: "test@test.iam.gserviceaccount.com",
          client_id: "123"
        }.to_json)
    }

      before do
        allow_any_instance_of(Pricing::Entitlements).to receive(:review_monitoring_enabled?).and_return(true)
        allow_any_instance_of(Pricing::Entitlements).to receive(:analytics_dashboard_enabled?).and_return(true)
        allow_any_instance_of(Pricing::Entitlements).to receive(:custom_product_pages_enabled?).and_return(true)
        allow_any_instance_of(Pricing::Entitlements).to receive(:keyword_tracking_enabled?).and_return(true)
      end

      it "enqueues all six jobs" do
        result = described_class.new(organization: organization, force: true).call
        expect(AppStoreConnectSyncJob).to have_been_enqueued.with(organization.id)
        expect(GooglePlaySyncJob).to have_been_enqueued.with(organization.id)
        expect(ReviewSyncJob).to have_been_enqueued.with(organization_id: organization.id)
        expect(AnalyticsSyncJob).to have_been_enqueued.with(organization_id: organization.id)
        expect(CppSyncJob).to have_been_enqueued.with(organization_id: organization.id)
        expect(Aso::KeywordRankCheckJob).to have_been_enqueued.with(organization_id: organization.id)

        expect(result.keys).to match_array(%i[asc google_play reviews analytics cpp keywords_rank])
        expect(result[:asc]).to eq(:enqueued)
        expect(result[:reviews]).to eq(:enqueued)
      end

      it "seeds an OrgSyncRun row (status=running) before the worker starts, closing the status-poll race" do
        described_class.new(organization: organization, force: true).call

        %w[asc google_play reviews analytics cpp keywords_rank].each do |job_name|
          run = OrgSyncRun.find_by(organization: organization, job_name: job_name)
          expect(run).to be_present, "expected OrgSyncRun row for #{job_name}"
          expect(run.status).to eq("running"), "expected #{job_name} to be running, got #{run.status}"
        end
      end

      it "does not double-enqueue a standalone job when one is already running" do
        described_class.new(organization: organization, force: true).call
        clear_enqueued_jobs

        described_class.new(organization: organization, force: true).call
        expect(ReviewSyncJob).not_to have_been_enqueued
        expect(AnalyticsSyncJob).not_to have_been_enqueued
        expect(CppSyncJob).not_to have_been_enqueued
        expect(Aso::KeywordRankCheckJob).not_to have_been_enqueued
      end
    end

    context "with only ASC creds, Pro entitlements" do
      let!(:asc_cred) { create(:app_store_connect_credential, organization: organization, active: true) }

      before do
        allow_any_instance_of(Pricing::Entitlements).to receive(:review_monitoring_enabled?).and_return(true)
        allow_any_instance_of(Pricing::Entitlements).to receive(:analytics_dashboard_enabled?).and_return(true)
        allow_any_instance_of(Pricing::Entitlements).to receive(:custom_product_pages_enabled?).and_return(true)
        allow_any_instance_of(Pricing::Entitlements).to receive(:keyword_tracking_enabled?).and_return(true)
      end

      it "does not enqueue GooglePlaySyncJob" do
        described_class.new(organization: organization, force: true).call
        expect(AppStoreConnectSyncJob).to have_been_enqueued
        expect(GooglePlaySyncJob).not_to have_been_enqueued
        expect(CppSyncJob).to have_been_enqueued
      end
    end

    context "when ASC sync is freshness-blocked (just synced)" do
      let!(:asc_cred) do
        create(:app_store_connect_credential, organization: organization, active: true, last_synced_at: 10.seconds.ago)
      end

      before do
        allow_any_instance_of(Pricing::Entitlements).to receive(:review_monitoring_enabled?).and_return(false)
        allow_any_instance_of(Pricing::Entitlements).to receive(:analytics_dashboard_enabled?).and_return(false)
        allow_any_instance_of(Pricing::Entitlements).to receive(:custom_product_pages_enabled?).and_return(false)
        allow_any_instance_of(Pricing::Entitlements).to receive(:keyword_tracking_enabled?).and_return(false)
      end

      it "returns :fresh for ASC and does not enqueue the job" do
        result = described_class.new(organization: organization, force: false).call
        expect(result[:asc]).to eq(:fresh)
        expect(AppStoreConnectSyncJob).not_to have_been_enqueued
      end

      it "bypasses freshness when force: true" do
        result = described_class.new(organization: organization, force: true).call
        expect(result[:asc]).to eq(:enqueued)
        expect(AppStoreConnectSyncJob).to have_been_enqueued
      end
    end
  end
end
