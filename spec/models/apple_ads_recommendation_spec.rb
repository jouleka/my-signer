require "rails_helper"

RSpec.describe AppleAdsRecommendation, type: :model do
  describe "validations" do
    it "is valid with all required fields" do
      expect(build(:apple_ads_recommendation)).to be_valid
    end

    it "requires keyword" do
      expect(build(:apple_ads_recommendation, keyword: nil)).not_to be_valid
    end

    it "enforces max length 100 on keyword" do
      expect(build(:apple_ads_recommendation, keyword: "a" * 100)).to be_valid
      expect(build(:apple_ads_recommendation, keyword: "a" * 101)).not_to be_valid
    end

    it "requires search_popularity" do
      expect(build(:apple_ads_recommendation, search_popularity: nil)).not_to be_valid
    end

    it "rejects search_popularity below 5 or above 100" do
      expect(build(:apple_ads_recommendation, search_popularity: 4)).not_to be_valid
      expect(build(:apple_ads_recommendation, search_popularity: 5)).to be_valid
      expect(build(:apple_ads_recommendation, search_popularity: 100)).to be_valid
      expect(build(:apple_ads_recommendation, search_popularity: 101)).not_to be_valid
    end

    it "requires search_popularity_updated_at" do
      expect(build(:apple_ads_recommendation, search_popularity_updated_at: nil)).not_to be_valid
    end

    it "enforces uniqueness on (apple_app, keyword)" do
      app = create(:apple_app)
      create(:apple_ads_recommendation, apple_app: app, keyword: "x")
      dup = build(:apple_ads_recommendation, apple_app: app, keyword: "x")
      expect(dup).not_to be_valid
    end

    it "allows the same keyword across different apple_apps" do
      org = create(:organization)
      app1 = create(:apple_app, organization: org, sku: "sku-1")
      app2 = create(:apple_app, organization: org, sku: "sku-2")
      create(:apple_ads_recommendation, apple_app: app1, keyword: "same")
      expect(build(:apple_ads_recommendation, apple_app: app2, keyword: "same")).to be_valid
    end
  end

  describe "normalization" do
    it "normalizes the keyword at write (NFC + downcase + collapse whitespace)" do
      app = create(:apple_app)
      rec = create(:apple_ads_recommendation, apple_app: app, keyword: "  Photo   EDITOR  ")
      expect(rec.keyword).to eq("photo editor")
    end
  end

  describe "associations" do
    it "belongs_to apple_app" do
      rec = create(:apple_ads_recommendation)
      expect(rec.apple_app).to be_a(AppleApp)
    end

    it "is destroyed when the AppleApp is destroyed" do
      app = create(:apple_app)
      create(:apple_ads_recommendation, apple_app: app)
      expect { app.destroy! }.to change { AppleAdsRecommendation.count }.by(-1)
    end
  end

  describe ".most_popular scope" do
    it "orders by search_popularity DESC" do
      app = create(:apple_app)
      low = create(:apple_ads_recommendation, apple_app: app, keyword: "low", search_popularity: 20)
      high = create(:apple_ads_recommendation, apple_app: app, keyword: "high", search_popularity: 90)
      mid = create(:apple_ads_recommendation, apple_app: app, keyword: "mid", search_popularity: 50)
      expect(described_class.most_popular.pluck(:keyword)).to eq(%w[high mid low])
    end
  end
end
