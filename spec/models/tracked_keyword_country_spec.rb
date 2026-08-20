require "rails_helper"

RSpec.describe TrackedKeywordCountry, type: :model do
  let(:organization) { create(:organization) }
  let(:apple_app) { create(:apple_app, organization: organization) }
  let(:tracked_keyword) { create(:tracked_keyword, apple_app: apple_app) }

  describe "validations" do
    it "is valid with valid attributes" do
      tkc = build(:tracked_keyword_country, tracked_keyword: tracked_keyword, country: "us")
      expect(tkc).to be_valid
    end

    it "requires country" do
      tkc = build(:tracked_keyword_country, tracked_keyword: tracked_keyword, country: nil)
      expect(tkc).not_to be_valid
      expect(tkc.errors[:country]).to include("can't be blank")
    end

    it "rejects a country not in Aso::Countries::SUPPORTED" do
      tkc = build(:tracked_keyword_country, tracked_keyword: tracked_keyword, country: "zz")
      expect(tkc).not_to be_valid
      expect(tkc.errors[:country]).to be_present
    end

    it "accepts every country listed in Aso::Countries::SUPPORTED" do
      Aso::Countries::SUPPORTED.each do |code|
        tk = create(:tracked_keyword, apple_app: apple_app, keyword: "kw-#{code}")
        tkc = build(:tracked_keyword_country, tracked_keyword: tk, country: code)
        expect(tkc).to be_valid, "expected #{code.inspect} to be accepted"
      end
    end

    it "enforces uniqueness on (tracked_keyword, country)" do
      create(:tracked_keyword_country, tracked_keyword: tracked_keyword, country: "us")
      dup = build(:tracked_keyword_country, tracked_keyword: tracked_keyword, country: "us")
      expect(dup).not_to be_valid
      expect(dup.errors[:country]).to be_present
    end

    it "allows the same country across different tracked_keywords" do
      other_kw = create(:tracked_keyword, apple_app: apple_app, keyword: "other")
      create(:tracked_keyword_country, tracked_keyword: tracked_keyword, country: "us")
      tkc = build(:tracked_keyword_country, tracked_keyword: other_kw, country: "us")
      expect(tkc).to be_valid
    end

    it "allows nil current_rank" do
      tkc = build(:tracked_keyword_country, tracked_keyword: tracked_keyword, country: "us", current_rank: nil)
      expect(tkc).to be_valid
    end

    it "rejects current_rank of 0" do
      tkc = build(:tracked_keyword_country, tracked_keyword: tracked_keyword, country: "us", current_rank: 0)
      expect(tkc).not_to be_valid
    end

    it "rejects current_rank above 250" do
      tkc = build(:tracked_keyword_country, tracked_keyword: tracked_keyword, country: "us", current_rank: 251)
      expect(tkc).not_to be_valid
    end

    it "accepts current_rank of 1" do
      tkc = build(:tracked_keyword_country, tracked_keyword: tracked_keyword, country: "us", current_rank: 1)
      expect(tkc).to be_valid
    end

    it "accepts current_rank of 250" do
      tkc = build(:tracked_keyword_country, tracked_keyword: tracked_keyword, country: "us", current_rank: 250)
      expect(tkc).to be_valid
    end
  end

  describe "associations" do
    it "belongs to tracked_keyword" do
      tkc = create(:tracked_keyword_country, tracked_keyword: tracked_keyword)
      expect(tkc.tracked_keyword).to eq(tracked_keyword)
    end

    it "exposes apple_app through tracked_keyword" do
      tkc = create(:tracked_keyword_country, tracked_keyword: tracked_keyword)
      expect(tkc.apple_app).to eq(apple_app)
    end

    it "exposes organization through apple_app" do
      tkc = create(:tracked_keyword_country, tracked_keyword: tracked_keyword)
      expect(tkc.organization).to eq(organization)
    end
  end

  describe "keyword_rankings association" do
    let(:tkc) { create(:tracked_keyword_country) }

    it "nullifies tracked_keyword_country_id on dependent rankings when destroyed (preserves history)" do
      ranking = KeywordRanking.create!(
        organization: tkc.organization,
        tracked_keyword_country: tkc,
        keyword: tkc.tracked_keyword.keyword,
        rank: 10,
        checked_on: Date.current
      )
      expect { tkc.destroy! }.to change { TrackedKeywordCountry.count }.by(-1)
      expect(ranking.reload.tracked_keyword_country_id).to be_nil
      expect(KeywordRanking).to exist(id: ranking.id)  # history preserved
    end

    it "can be destroyed when no rankings exist" do
      tkc2 = create(:tracked_keyword_country)
      expect { tkc2.destroy! }.to change { TrackedKeywordCountry.count }.by(-1)
    end
  end

  describe "defaults" do
    it "defaults enabled to true" do
      expect(create(:tracked_keyword_country).enabled).to be true
    end
  end
end
