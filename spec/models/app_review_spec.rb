require "rails_helper"

RSpec.describe AppReview, type: :model do
  describe "validations" do
    let(:organization) { create(:organization) }
    let(:apple_app) { create(:apple_app, organization: organization) }

    it "is valid with valid attributes" do
      review = build(:app_review, organization: organization, reviewable: apple_app)
      expect(review).to be_valid
    end

    it "requires remote_id" do
      review = build(:app_review, remote_id: nil)
      expect(review).not_to be_valid
    end

    it "requires rating between 1-5" do
      review = build(:app_review, rating: 0)
      expect(review).not_to be_valid
      review.rating = 6
      expect(review).not_to be_valid
      review.rating = 3
      expect(review).to be_valid
    end

    it "requires body" do
      review = build(:app_review, body: nil)
      expect(review).not_to be_valid
    end

    it "requires reviewed_at" do
      review = build(:app_review, reviewed_at: nil)
      expect(review).not_to be_valid
    end

    it "enforces remote_id uniqueness scoped to reviewable" do
      create(:app_review, organization: organization, reviewable: apple_app, remote_id: "abc")
      duplicate = build(:app_review, organization: organization, reviewable: apple_app, remote_id: "abc")
      expect(duplicate).not_to be_valid
    end

    it "allows same remote_id for different reviewables" do
      android_app = create(:android_app, organization: organization)
      create(:app_review, organization: organization, reviewable: apple_app, remote_id: "abc")
      review2 = build(:app_review, organization: organization, reviewable: android_app, remote_id: "abc")
      expect(review2).to be_valid
    end
  end

  describe "#compute_sentiment" do
    it "sets negative for 1-star on save" do
      review = create(:app_review, rating: 1, body: "Terrible")
      expect(review.sentiment).to eq("negative")
    end

    it "sets negative for 2-star on save" do
      review = create(:app_review, rating: 2, body: "Bad")
      expect(review.sentiment).to eq("negative")
    end

    it "sets neutral for 3-star on save" do
      review = create(:app_review, rating: 3, body: "Okay")
      expect(review.sentiment).to eq("neutral")
    end

    it "sets positive for 4-star on save" do
      review = create(:app_review, rating: 4, body: "Good")
      expect(review.sentiment).to eq("positive")
    end

    it "sets positive for 5-star on save" do
      review = create(:app_review, rating: 5, body: "Amazing")
      expect(review.sentiment).to eq("positive")
    end
  end

  describe "scopes" do
    let(:organization) { create(:organization) }
    let(:apple_app) { create(:apple_app, organization: organization) }
    let(:android_app) { create(:android_app, organization: organization) }

    let!(:positive_review) { create(:app_review, organization: organization, reviewable: apple_app, rating: 5) }
    let!(:negative_review) { create(:app_review, :negative, organization: organization, reviewable: apple_app) }
    let!(:neutral_review) { create(:app_review, :neutral, organization: organization, reviewable: apple_app) }
    let!(:android_review) { create(:app_review, organization: organization, reviewable: android_app, rating: 4) }
    let!(:replied_review) { create(:app_review, :with_reply, organization: organization, reviewable: apple_app) }

    it ".negative returns 1-2 star reviews" do
      expect(AppReview.negative).to include(negative_review)
      expect(AppReview.negative).not_to include(positive_review, neutral_review)
    end

    it ".positive returns 4-5 star reviews" do
      expect(AppReview.positive).to include(positive_review, android_review, replied_review)
      expect(AppReview.positive).not_to include(negative_review, neutral_review)
    end

    it ".neutral returns 3 star reviews" do
      expect(AppReview.neutral).to include(neutral_review)
      expect(AppReview.neutral).not_to include(positive_review, negative_review)
    end

    it ".unanswered returns reviews with no reply" do
      expect(AppReview.unanswered).to include(positive_review, negative_review, neutral_review, android_review)
      expect(AppReview.unanswered).not_to include(replied_review)
    end

    it ".by_platform filters by platform" do
      expect(AppReview.by_platform("apple")).to include(positive_review)
      expect(AppReview.by_platform("apple")).not_to include(android_review)
      expect(AppReview.by_platform("android")).to include(android_review)
      expect(AppReview.by_platform("android")).not_to include(positive_review)
    end
  end

  describe "#platform" do
    it "returns :apple for AppleApp" do
      review = build(:app_review)
      expect(review.platform).to eq(:apple)
    end

    it "returns :android for AndroidApp" do
      review = build(:app_review, :android)
      expect(review.platform).to eq(:android)
    end
  end
end
