require "rails_helper"

RSpec.describe RatingSnapshot, type: :model do
  describe "validations" do
    let(:organization) { create(:organization) }
    let(:apple_app) { create(:apple_app, organization: organization) }

    it "is valid with valid attributes" do
      snapshot = build(:rating_snapshot, organization: organization, snapshotable: apple_app)
      expect(snapshot).to be_valid
    end

    it "requires snapshot_date" do
      snapshot = build(:rating_snapshot, snapshot_date: nil)
      expect(snapshot).not_to be_valid
    end

    it "requires average_rating" do
      snapshot = build(:rating_snapshot, average_rating: nil)
      expect(snapshot).not_to be_valid
    end

    it "enforces snapshot_date uniqueness scoped to snapshotable" do
      create(:rating_snapshot, organization: organization, snapshotable: apple_app, snapshot_date: Date.current)
      duplicate = build(:rating_snapshot, organization: organization, snapshotable: apple_app, snapshot_date: Date.current)
      expect(duplicate).not_to be_valid
    end

    it "allows same date for different snapshotables" do
      android_app = create(:android_app, organization: organization)
      create(:rating_snapshot, organization: organization, snapshotable: apple_app, snapshot_date: Date.current)
      snapshot2 = build(:rating_snapshot, organization: organization, snapshotable: android_app, snapshot_date: Date.current)
      expect(snapshot2).to be_valid
    end
  end

  describe "scopes" do
    let(:organization) { create(:organization) }
    let(:apple_app) { create(:apple_app, organization: organization) }

    it ".last_n_days returns snapshots within range" do
      recent = create(:rating_snapshot, organization: organization, snapshotable: apple_app, snapshot_date: 5.days.ago.to_date)
      old = create(:rating_snapshot, organization: organization, snapshotable: apple_app, snapshot_date: 40.days.ago.to_date)

      expect(RatingSnapshot.last_n_days(30)).to include(recent)
      expect(RatingSnapshot.last_n_days(30)).not_to include(old)
    end
  end
end
