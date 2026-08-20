require "rails_helper"

RSpec.describe Pricing::Entitlements, type: :service do
  describe ".for_user" do
    it "defaults nil users to the free plan" do
      entitlements = described_class.for_user(nil)

      expect(entitlements.tier).to eq("free")
      expect(entitlements.max_owned_organizations).to eq(1)
      expect(entitlements.max_screenshot_scenes_per_project).to eq(5)
      expect(entitlements.store_upload_enabled?).to be(false)
      expect(entitlements.scheduled_sync_enabled?).to be(true)
    end

    it "returns the pro catalog for pro users" do
      user = create(:user, :pro_plan)
      entitlements = described_class.for_user(user)

      expect(entitlements.tier).to eq("pro")
      expect(entitlements.max_owned_organizations).to eq(3)
      expect(entitlements.max_seats_per_organization).to eq(1)
      expect(entitlements.max_screenshot_projects_per_organization).to eq(10)
      expect(entitlements.max_screenshot_scenes_per_project).to eq(10)
      expect(entitlements.max_store_uploads_per_day_per_organization).to eq(60)
      expect(entitlements.store_upload_enabled?).to be(true)
      expect(entitlements.scheduled_sync_enabled?).to be(true)
      expect(entitlements.next_plan_tier).to eq("team")
    end

    it "returns the team catalog for team users" do
      user = create(:user, :team_plan)
      entitlements = described_class.for_user(user)

      expect(entitlements.tier).to eq("team")
      expect(entitlements.max_owned_organizations).to eq(10)
      expect(entitlements.max_seats_per_organization).to eq(10)
      expect(entitlements.max_screenshot_projects_per_organization).to eq(30)
      expect(entitlements.max_screenshot_scenes_per_project).to eq(15)
      expect(entitlements.max_media_storage_bytes_per_organization).to eq(10.gigabytes)
      expect(entitlements.next_plan_tier).to be_nil
    end
  end

  describe ".required_plan_for" do
    it "maps paid automation features to pro" do
      expect(described_class.required_plan_for(:store_uploads)).to eq("pro")
    end

    it "maps BYOK to the team plan" do
      expect(described_class.required_plan_for(:byok)).to eq("team")
    end
  end

  describe "#byok_enabled?" do
    it "is disabled on the free and pro tiers" do
      expect(described_class.new("free").byok_enabled?).to be(false)
      expect(described_class.new("pro").byok_enabled?).to be(false)
    end

    it "is enabled on the team tier" do
      expect(described_class.new("team").byok_enabled?).to be(true)
    end
  end

  describe "#next_plan_that_raises" do
    it "skips plans that do not actually raise the seat limit" do
      # Free and Pro both cap seats at 1; Team is the first tier that raises it.
      expect(described_class.new("free").next_plan_that_raises(:max_seats_per_organization)).to eq("team")
      expect(described_class.new("pro").next_plan_that_raises(:max_seats_per_organization)).to eq("team")
    end

    it "returns the adjacent tier when it already raises the limit" do
      expect(described_class.new("free").next_plan_that_raises(:max_owned_organizations)).to eq("pro")
      expect(described_class.new("pro").next_plan_that_raises(:max_owned_organizations)).to eq("team")
    end

    it "returns nil on the top tier" do
      expect(described_class.new("team").next_plan_that_raises(:max_seats_per_organization)).to be_nil
    end
  end

  describe "#to_h" do
    it "returns a compact limits and features snapshot" do
      snapshot = described_class.new("free").to_h

      expect(snapshot[:tier]).to eq("free")
      expect(snapshot[:limits][:owned_organizations]).to eq(1)
      expect(snapshot[:features][:manual_sync]).to be(true)
      expect(snapshot[:features][:store_uploads]).to be(false)
    end
  end

  describe "keyword tracker entitlements" do
    describe "Free tier" do
      subject { described_class.new("free") }

      it "has max_countries_per_tracked_keyword = 1" do
        expect(subject.max_countries_per_tracked_keyword).to eq(1)
      end

      it "has max_keyword_history_days = 7" do
        expect(subject.max_keyword_history_days).to eq(7)
      end

      it "has keyword_tracking_refresh_days = 7" do
        expect(subject.keyword_tracking_refresh_days).to eq(7)
      end

      it "has keyword_tracking_priority_queue? false" do
        expect(subject.keyword_tracking_priority_queue?).to be false
      end

      it "has keyword_rank_alerts_enabled? false" do
        expect(subject.keyword_rank_alerts_enabled?).to be false
      end

      it "has apple_ads_integration_enabled? false" do
        expect(subject.apple_ads_integration_enabled?).to be false
      end
    end

    describe "Pro tier" do
      subject { described_class.new("pro") }

      it { expect(subject.max_countries_per_tracked_keyword).to eq(3) }
      it { expect(subject.max_keyword_history_days).to eq(90) }
      it { expect(subject.keyword_tracking_refresh_days).to eq(1) }
      it { expect(subject.keyword_tracking_priority_queue?).to be false }
      it { expect(subject.keyword_rank_alerts_enabled?).to be false }
      it { expect(subject.apple_ads_integration_enabled?).to be true }
    end

    describe "Team tier" do
      subject { described_class.new("team") }

      it { expect(subject.max_countries_per_tracked_keyword).to eq(999) }
      it { expect(subject.max_keyword_history_days).to eq(365) }
      it { expect(subject.keyword_tracking_refresh_days).to eq(1) }
      it { expect(subject.keyword_tracking_priority_queue?).to be true }
      it { expect(subject.keyword_rank_alerts_enabled?).to be true }
      it { expect(subject.apple_ads_integration_enabled?).to be true }
    end
  end
end
