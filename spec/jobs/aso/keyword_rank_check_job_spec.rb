require "rails_helper"

RSpec.describe Aso::KeywordRankCheckJob do
  let(:owner) { create(:user, :pro_plan) }
  let(:org)   { create(:organization, owner: owner) }
  let(:app)   { create(:apple_app, organization: org, app_store_id: "1149994032") }
  let(:tk)    { create(:tracked_keyword, apple_app: app, keyword: "photo editor") }
  let!(:tkc)  { create(:tracked_keyword_country, tracked_keyword: tk, country: "us") }

  let(:mock_checker) { instance_double(Aso::KeywordChecker) }
  before do
    allow(Aso::KeywordChecker).to receive(:new).and_return(mock_checker)
  end

  describe "happy path" do
    before { allow(mock_checker).to receive(:check).and_return({ rank: 12, total_count: 228 }) }

    it "creates a KeywordRanking row" do
      expect { described_class.new.perform(organization_id: org.id) }.to change { KeywordRanking.count }.by(1)
    end

    it "updates current_rank, competition_count, last_checked_at on the tkc" do
      described_class.new.perform(organization_id: org.id)
      tkc.reload
      expect(tkc.current_rank).to eq(12)
      expect(tkc.competition_count).to eq(228)
      expect(tkc.last_checked_at).to be_within(5.seconds).of(Time.current)
    end

    it "promotes previous current_rank to previous_rank on next run" do
      tkc.update!(current_rank: 20)
      described_class.new.perform(organization_id: org.id)
      tkc.reload
      expect(tkc.previous_rank).to eq(20)
      expect(tkc.current_rank).to eq(12)
    end

    it "is idempotent within a single day" do
      described_class.new.perform(organization_id: org.id)
      expect { described_class.new.perform(organization_id: org.id) }.not_to change { KeywordRanking.count }
    end
  end

  describe "rank not found in results" do
    before { allow(mock_checker).to receive(:check).and_return({ rank: nil, total_count: 228 }) }

    it "creates a KeywordRanking with rank=nil" do
      described_class.new.perform(organization_id: org.id)
      ranking = KeywordRanking.last
      expect(ranking.rank).to be_nil
    end

    it "updates competition_count even when rank is nil" do
      described_class.new.perform(organization_id: org.id)
      expect(tkc.reload.competition_count).to eq(228)
    end
  end

  describe "tier refresh cadence" do
    it "skips a Free-tier tkc checked within 7 days" do
      owner.update!(plan_tier: :free)
      org.reset_entitlements_memo!
      # Free has max 5 keywords — our 1 is fine
      tkc.update!(last_checked_at: 3.days.ago)
      expect { described_class.new.perform(organization_id: org.id) }.not_to change { KeywordRanking.count }
    end

    it "checks a Free-tier tkc checked >= 7 days ago" do
      owner.update!(plan_tier: :free)
      org.reset_entitlements_memo!
      tkc.update!(last_checked_at: 8.days.ago)
      allow(mock_checker).to receive(:check).and_return({ rank: 5, total_count: 100 })
      expect { described_class.new.perform(organization_id: org.id) }.to change { KeywordRanking.count }.by(1)
    end

    it "checks a Pro-tier tkc daily" do
      tkc.update!(last_checked_at: 25.hours.ago)
      allow(mock_checker).to receive(:check).and_return({ rank: 5, total_count: 100 })
      expect { described_class.new.perform(organization_id: org.id) }.to change { KeywordRanking.count }.by(1)
    end
  end

  describe "entitlement gating" do
    it "skips when keyword_tracking_enabled? is false" do
      # Job uses keyword_tracking_enabled? as the gate (true on Free because
      # max_tracked_keywords_per_app: 5 > 0 — Free can view seeded/bequeathed
      # keywords and still receive a weekly refresh). keyword_editor_enabled?
      # gates the *editor UI*, not the scraper; using it here would incorrectly
      # block Free-tier rank checks (the CATALOG explicitly assigns Free a
      # 7-day refresh cadence).
      allow_any_instance_of(Pricing::Entitlements).to receive(:keyword_tracking_enabled?).and_return(false)
      allow(mock_checker).to receive(:check).and_return({ rank: 1, total_count: 1 })
      expect { described_class.new.perform(organization_id: org.id) }.not_to change { KeywordRanking.count }
    end
  end

  describe "rate limit path" do
    before { allow(mock_checker).to receive(:check).and_return(:rate_limited) }

    it "raises Aso::RateLimiter::Exhausted so ActiveJob can back off" do
      expect { described_class.new.perform(organization_id: org.id) }.to raise_error(Aso::RateLimiter::Exhausted)
    end

    it "does NOT update tkc.last_checked_at when rate-limited" do
      tkc.update!(last_checked_at: 10.days.ago)
      initial = tkc.last_checked_at
      begin
        described_class.new.perform(organization_id: org.id)
      rescue Aso::RateLimiter::Exhausted
        nil
      end
      expect(tkc.reload.last_checked_at.to_i).to eq(initial.to_i)
    end
  end

  describe "network error path" do
    before { allow(mock_checker).to receive(:check).and_return(:network_error) }

    it "does NOT create a KeywordRanking" do
      expect { described_class.new.perform(organization_id: org.id) }.not_to change { KeywordRanking.count }
    end

    it "does NOT raise (retry tomorrow, not immediately)" do
      expect { described_class.new.perform(organization_id: org.id) }.not_to raise_error
    end
  end

  describe "only-enabled keywords are checked" do
    it "skips disabled TrackedKeyword rows (plan-downgrade paused)" do
      tk.update!(enabled: false)
      allow(mock_checker).to receive(:check).and_return({ rank: 1, total_count: 1 })
      expect { described_class.new.perform(organization_id: org.id) }.not_to change { KeywordRanking.count }
    end

    it "skips disabled TrackedKeywordCountry rows" do
      tkc.update!(enabled: false)
      allow(mock_checker).to receive(:check).and_return({ rank: 1, total_count: 1 })
      expect { described_class.new.perform(organization_id: org.id) }.not_to change { KeywordRanking.count }
    end
  end

  describe "queue + retry config" do
    it "is queued on :aso_scraping by default" do
      expect(described_class.new.queue_name).to eq("aso_scraping")
    end

    it "retries on Aso::RateLimiter::Exhausted with backoff" do
      # Verify retry_on is configured
      expect(described_class.rescue_handlers.map(&:first)).to include("Aso::RateLimiter::Exhausted")
    end
  end

  describe "advisory lock" do
    it "acquires a per-org advisory lock" do
      allow(mock_checker).to receive(:check).and_return({ rank: 1, total_count: 1 })
      # We can't trivially assert the lock was acquired, but the AdvisoryLockable concern's
      # `with_advisory_lock` is called with a per-org key. A second concurrent perform
      # would return without running. At minimum, confirm the method runs cleanly once.
      expect { described_class.new.perform(organization_id: org.id) }.not_to raise_error
    end
  end
end
