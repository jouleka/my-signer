require "rails_helper"

RSpec.describe "Organization unified sync", type: :request do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }

  before do
    sign_in user, scope: :user
    Rails.cache.clear
  end

  describe "POST /organizations/:id/sync_all" do
    context "with no creds and no premium entitlements" do
      before do
        allow_any_instance_of(Pricing::Entitlements).to receive(:review_monitoring_enabled?).and_return(false)
        allow_any_instance_of(Pricing::Entitlements).to receive(:analytics_dashboard_enabled?).and_return(false)
        allow_any_instance_of(Pricing::Entitlements).to receive(:custom_product_pages_enabled?).and_return(false)
        allow_any_instance_of(Pricing::Entitlements).to receive(:keyword_tracking_enabled?).and_return(false)
      end

      it "returns 202 with dispatched: {}" do
        post sync_all_organization_path(organization)
        expect(response).to have_http_status(:accepted)
        expect(JSON.parse(response.body)["dispatched"]).to eq({})
      end
    end

    context "with ASC creds + Pro entitlements" do
      let!(:asc_cred) { create(:app_store_connect_credential, organization: organization, active: true) }

      before do
        allow_any_instance_of(Pricing::Entitlements).to receive(:review_monitoring_enabled?).and_return(true)
        allow_any_instance_of(Pricing::Entitlements).to receive(:analytics_dashboard_enabled?).and_return(true)
        allow_any_instance_of(Pricing::Entitlements).to receive(:custom_product_pages_enabled?).and_return(true)
        allow_any_instance_of(Pricing::Entitlements).to receive(:keyword_tracking_enabled?).and_return(true)
        ActiveJob::Base.queue_adapter = :test
      end

      it "enqueues ASC + reviews + analytics + cpp + keywords" do
        post sync_all_organization_path(organization), params: { force: true }
        expect(response).to have_http_status(:accepted)
        expect(AppStoreConnectSyncJob).to have_been_enqueued
        expect(ReviewSyncJob).to have_been_enqueued
        expect(AnalyticsSyncJob).to have_been_enqueued
        expect(CppSyncJob).to have_been_enqueued
        expect(Aso::KeywordRankCheckJob).to have_been_enqueued
      end

      it "writes an audit event with action sync_all_triggered" do
        expect {
          post sync_all_organization_path(organization), params: { force: true }
        }.to change { AuditEvent.where(action: "sync_all_triggered").count }.by(1)
      end
    end
  end

  describe "GET /organizations/:id/sync_status_all" do
    it "returns the aggregator payload" do
      OrgSyncRun.create!(organization: organization, job_name: "asc", status: "ok",
                         started_at: 2.minutes.ago, finished_at: 1.minute.ago)

      get sync_status_all_organization_path(organization)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["running"]).to be false
      expect(json["last_sync_status"]).to eq("ok")
      expect(json["jobs"].keys).to include("asc")
    end
  end
end
