require "rails_helper"

RSpec.describe AppAnalyticsSnapshot, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      snapshot = build(:app_analytics_snapshot)
      expect(snapshot).to be_valid
    end

    it "enforces uniqueness on snapshotable + date" do
      existing = create(:app_analytics_snapshot)
      duplicate = build(:app_analytics_snapshot,
        organization: existing.organization,
        snapshotable: existing.snapshotable,
        snapshot_date: existing.snapshot_date)
      expect(duplicate).not_to be_valid
    end

    it "requires snapshot_date" do
      snapshot = build(:app_analytics_snapshot, snapshot_date: nil)
      expect(snapshot).not_to be_valid
    end
  end

  describe "scopes" do
    it ".last_n_days returns snapshots within range" do
      recent = create(:app_analytics_snapshot, snapshot_date: 2.days.ago.to_date)
      old = create(:app_analytics_snapshot, snapshot_date: 60.days.ago.to_date,
        snapshotable: create(:apple_app))
      expect(described_class.last_n_days(30)).to include(recent)
      expect(described_class.last_n_days(30)).not_to include(old)
    end
  end

  describe "#computed_conversion_rate" do
    it "calculates rate from downloads and impressions" do
      snapshot = build(:app_analytics_snapshot, total_downloads: 50, impressions: 1000)
      expect(snapshot.computed_conversion_rate).to eq(5.0)
    end

    it "returns 0 when impressions are zero" do
      snapshot = build(:app_analytics_snapshot, total_downloads: 50, impressions: 0)
      expect(snapshot.computed_conversion_rate).to eq(0.0)
    end
  end

  describe "#apple? and #android?" do
    it "returns true for apple snapshotable" do
      snapshot = build(:app_analytics_snapshot)
      expect(snapshot.apple?).to be true
      expect(snapshot.android?).to be false
    end
  end
end
