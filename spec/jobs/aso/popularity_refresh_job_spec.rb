require "rails_helper"

RSpec.describe Aso::PopularityRefreshJob do
  let(:org)  { create(:organization, owner: create(:user, :pro_plan)) }
  let(:app)  { create(:apple_app, organization: org, app_store_id: "1149994032") }
  let!(:credential) { create(:apple_ads_credential, organization: org, last_successful_at: 1.hour.ago) }

  let(:mock_client) { instance_double(Aso::AppleAds::Client) }
  before do
    allow(Aso::AppleAds::Client).to receive(:new).with(credential: credential).and_return(mock_client)
    allow(mock_client).to receive(:recommended_keywords).and_return([
      { keyword: "photo editor", search_popularity: 85, bid_amount_micros: 1_500_000 },
      { keyword: "photoshop",    search_popularity: 78, bid_amount_micros: nil }
    ])
  end

  describe "happy path" do
    it "upserts into apple_ads_recommendations" do
      app  # force-create
      expect {
        described_class.new.perform(organization_id: org.id)
      }.to change { AppleAdsRecommendation.count }.by(2)
    end

    it "updates search_popularity on matching enabled TrackedKeyword rows" do
      app
      tk = create(:tracked_keyword, apple_app: app, keyword: "photo editor", enabled: true)
      described_class.new.perform(organization_id: org.id)
      expect(tk.reload.search_popularity).to eq(85)
      expect(tk.search_popularity_updated_at).to be_within(5.seconds).of(Time.current)
    end

    it "does NOT update disabled (paused) TrackedKeyword rows" do
      app
      tk = create(:tracked_keyword, apple_app: app, keyword: "photo editor", enabled: false, search_popularity: 10)
      described_class.new.perform(organization_id: org.id)
      expect(tk.reload.search_popularity).to eq(10)
    end

    it "marks credential as successful after a clean run" do
      app
      credential.update!(last_error: "old error")
      described_class.new.perform(organization_id: org.id)
      expect(credential.reload.last_error).to be_nil
      expect(credential.reload.last_successful_at).to be_within(5.seconds).of(Time.current)
    end
  end

  describe "upsert semantics" do
    it "updates existing recommendations instead of inserting duplicates" do
      app
      existing = create(:apple_ads_recommendation, apple_app: app, keyword: "photo editor", search_popularity: 10, bid_amount_micros: 100_000)
      expect {
        described_class.new.perform(organization_id: org.id)
      }.to change { AppleAdsRecommendation.count }.by(1)  # only photoshop is new
      expect(existing.reload.search_popularity).to eq(85)
      expect(existing.bid_amount_micros).to eq(1_500_000)
    end
  end

  describe "entitlement gating" do
    it "skips when apple_ads_integration_enabled? is false (trial→Free downgrade case)" do
      org.owner.update!(plan_tier: :free)
      org.reset_entitlements_memo!
      app
      expect { described_class.new.perform(organization_id: org.id) }.not_to change { AppleAdsRecommendation.count }
      expect(mock_client).not_to have_received(:recommended_keywords)
    end
  end

  describe "credential gating" do
    it "skips when credential is missing" do
      credential.destroy
      org.reload
      app
      expect { described_class.new.perform(organization_id: org.id) }.not_to change { AppleAdsRecommendation.count }
    end

    it "skips when credential is never successful" do
      credential.update!(last_successful_at: nil)
      app
      expect { described_class.new.perform(organization_id: org.id) }.not_to change { AppleAdsRecommendation.count }
    end
  end

  describe "credential invalid path" do
    it "records the failure on the credential without raising" do
      app
      allow(mock_client).to receive(:recommended_keywords).and_raise(Aso::AppleAds::CredentialsInvalid, "401 Unauthorized")
      expect { described_class.new.perform(organization_id: org.id) }.not_to raise_error
      expect(credential.reload.last_error).to include("401")
    end

    it "bails out on CredentialsInvalid without calling additional apps" do
      # Create two apps, both should be visited unless we bail
      create(:apple_app, organization: org, sku: "sku-1", app_store_id: "111")
      create(:apple_app, organization: org, sku: "sku-2", app_store_id: "222")

      call_count = 0
      allow(mock_client).to receive(:recommended_keywords) do
        call_count += 1
        raise Aso::AppleAds::CredentialsInvalid, "401 Unauthorized"
      end

      described_class.new.perform(organization_id: org.id)

      # With bail-out, only ONE call happens (the first app), not two
      expect(call_count).to eq(1)
      expect(credential.reload.last_error).to include("401")
    end

    it "clears last_successful_at when credentials invalid mid-run" do
      create(:apple_app, organization: org, sku: "sku-1")
      # Set last_successful_at to a known past time
      stale_time = 2.days.ago
      credential.update!(last_successful_at: stale_time)

      allow(mock_client).to receive(:recommended_keywords).and_raise(Aso::AppleAds::CredentialsInvalid, "bad")

      described_class.new.perform(organization_id: org.id)

      # mark_failure! nulls out last_successful_at so the connection banner
      # correctly flips to a re-connect CTA and subsequent job runs skip
      # (see credential gating spec above) until the user rotates creds.
      expect(credential.reload.last_successful_at).to be_nil
      expect(credential).not_to be_last_successful
    end

    it "flips last_successful_at only on a full successful run" do
      app  # force create
      described_class.new.perform(organization_id: org.id)
      expect(credential.reload.last_successful_at).to be_within(5.seconds).of(Time.current)
    end
  end

  describe "transient errors" do
    it "propagates TransientError for ActiveJob retry" do
      app
      allow(mock_client).to receive(:recommended_keywords).and_raise(Aso::AppleAds::TransientError, "502")
      expect { described_class.new.perform(organization_id: org.id) }.to raise_error(Aso::AppleAds::TransientError)
    end

    it "propagates RateLimited for ActiveJob retry" do
      app
      allow(mock_client).to receive(:recommended_keywords).and_raise(Aso::AppleAds::RateLimited, "429")
      expect { described_class.new.perform(organization_id: org.id) }.to raise_error(Aso::AppleAds::RateLimited)
    end
  end

  describe "queue + retry config" do
    it "is queued on :default (not aso_scraping — Apple Ads API is separate from MZStore)" do
      expect(described_class.new.queue_name).to eq("default")
    end

    it "retries on TransientError" do
      expect(described_class.rescue_handlers.map(&:first)).to include("Aso::AppleAds::TransientError")
    end

    it "retries on RateLimited" do
      expect(described_class.rescue_handlers.map(&:first)).to include("Aso::AppleAds::RateLimited")
    end
  end
end
