require "rails_helper"

RSpec.describe TrackedKeyword, type: :model do
  let(:organization) { create(:organization) }
  let(:apple_app) { create(:apple_app, organization: organization) }

  describe "validations" do
    it "is valid with valid attributes" do
      tk = build(:tracked_keyword, apple_app: apple_app, keyword: "productivity")
      expect(tk).to be_valid
    end

    it "requires keyword" do
      tk = build(:tracked_keyword, apple_app: apple_app, keyword: nil)
      expect(tk).not_to be_valid
      expect(tk.errors[:keyword]).to include("can't be blank")
    end

    it "rejects keyword longer than 100 chars" do
      tk = build(:tracked_keyword, apple_app: apple_app, keyword: "a" * 101)
      expect(tk).not_to be_valid
      expect(tk.errors[:keyword]).to be_present
    end

    it "accepts keyword exactly 100 chars" do
      tk = build(:tracked_keyword, apple_app: apple_app, keyword: "a" * 100)
      expect(tk).to be_valid
    end

    it "normalizes keyword to NFC + downcase + stripped + whitespace-collapsed" do
      tk = create(:tracked_keyword, apple_app: apple_app, keyword: "  Photo   Éditor  ")
      expect(tk.keyword).to eq("photo éditor".unicode_normalize(:nfc))
    end

    it "enforces uniqueness on (apple_app, keyword)" do
      create(:tracked_keyword, apple_app: apple_app, keyword: "x")
      dup = build(:tracked_keyword, apple_app: apple_app, keyword: "x")
      expect(dup).not_to be_valid
      expect(dup.errors[:keyword]).to be_present
    end

    it "allows the same keyword across different apple_apps" do
      other_app = create(:apple_app)
      create(:tracked_keyword, apple_app: apple_app, keyword: "x")
      tk = build(:tracked_keyword, apple_app: other_app, keyword: "x")
      expect(tk).to be_valid
    end

    it "accepts a valid search_popularity_source" do
      tk = build(:tracked_keyword, apple_app: apple_app, search_popularity_source: "apple_ads_recommendations")
      expect(tk).to be_valid
    end

    it "rejects an unknown search_popularity_source" do
      tk = build(:tracked_keyword, apple_app: apple_app, search_popularity_source: "typo_bucket")
      expect(tk).not_to be_valid
      expect(tk.errors[:search_popularity_source]).to be_present
    end

    it "allows nil search_popularity" do
      tk = build(:tracked_keyword, apple_app: apple_app, search_popularity: nil)
      expect(tk).to be_valid
    end

    it "rejects search_popularity below 5" do
      tk = build(:tracked_keyword, apple_app: apple_app, search_popularity: 4)
      expect(tk).not_to be_valid
    end

    it "rejects search_popularity above 100" do
      tk = build(:tracked_keyword, apple_app: apple_app, search_popularity: 101)
      expect(tk).not_to be_valid
    end

    it "accepts search_popularity between 5 and 100" do
      tk = build(:tracked_keyword, apple_app: apple_app, search_popularity: 50)
      expect(tk).to be_valid
    end
  end

  describe "associations" do
    it "belongs to apple_app" do
      tk = create(:tracked_keyword, apple_app: apple_app)
      expect(tk.apple_app).to eq(apple_app)
    end

    it "has many tracked_keyword_countries" do
      tk = create(:tracked_keyword, apple_app: apple_app)
      create(:tracked_keyword_country, tracked_keyword: tk, country: "us")
      create(:tracked_keyword_country, tracked_keyword: tk, country: "gb")
      expect(tk.tracked_keyword_countries.pluck(:country)).to contain_exactly("us", "gb")
    end

    it "destroys dependent tracked_keyword_countries when destroyed" do
      tk = create(:tracked_keyword, apple_app: create(:apple_app))
      create(:tracked_keyword_country, tracked_keyword: tk, country: "us")
      expect { tk.destroy! }.to change { TrackedKeywordCountry.count }.by(-1)
    end

    it "AppleApp#destroy cascades through tracked_keywords" do
      app = create(:apple_app)
      tk = create(:tracked_keyword, apple_app: app)
      create(:tracked_keyword_country, tracked_keyword: tk)
      expect { app.destroy! }.to change { TrackedKeyword.count }.by(-1)
                           .and change { TrackedKeywordCountry.count }.by(-1)
    end
  end

  describe "defaults" do
    it "defaults enabled to true" do
      expect(create(:tracked_keyword).enabled).to be true
    end
  end
end
