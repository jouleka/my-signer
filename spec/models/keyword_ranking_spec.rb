require "rails_helper"

RSpec.describe KeywordRanking, type: :model do
  let(:organization) { create(:organization) }
  let(:apple_app) { create(:apple_app, organization: organization) }
  let(:tracked_keyword) { create(:tracked_keyword, apple_app: apple_app, keyword: "productivity") }
  let(:tkc) { create(:tracked_keyword_country, tracked_keyword: tracked_keyword, country: "us") }

  describe "validations" do
    it "is valid with valid attributes" do
      ranking = build(:keyword_ranking, organization: organization, tracked_keyword_country: tkc, keyword: tracked_keyword.keyword)
      expect(ranking).to be_valid
    end

    it "requires keyword" do
      ranking = build(:keyword_ranking, tracked_keyword_country: tkc, keyword: nil)
      expect(ranking).not_to be_valid
      expect(ranking.errors[:keyword]).to include("can't be blank")
    end

    it "requires checked_on" do
      ranking = build(:keyword_ranking, tracked_keyword_country: tkc, checked_on: nil)
      expect(ranking).not_to be_valid
      expect(ranking.errors[:checked_on]).to include("can't be blank")
    end

    it "enforces uniqueness on keyword + tracked_keyword_country + checked_on" do
      create(:keyword_ranking, organization: organization, tracked_keyword_country: tkc,
             keyword: "test", checked_on: Date.current)
      duplicate = build(:keyword_ranking, organization: organization, tracked_keyword_country: tkc,
                        keyword: "test", checked_on: Date.current)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:keyword]).to be_present
    end

    it "allows the same keyword on different dates" do
      create(:keyword_ranking, organization: organization, tracked_keyword_country: tkc,
             keyword: "test", checked_on: Date.yesterday)
      ranking = build(:keyword_ranking, organization: organization, tracked_keyword_country: tkc,
                      keyword: "test", checked_on: Date.current)
      expect(ranking).to be_valid
    end

    it "validates rank is greater than 0" do
      ranking = build(:keyword_ranking, tracked_keyword_country: tkc, rank: 0)
      expect(ranking).not_to be_valid
    end

    it "validates rank is at most 250" do
      ranking = build(:keyword_ranking, tracked_keyword_country: tkc, rank: 251)
      expect(ranking).not_to be_valid
    end

    it "allows nil rank" do
      ranking = build(:keyword_ranking, tracked_keyword_country: tkc, rank: nil)
      expect(ranking).to be_valid
    end

    it "allows rank of 1" do
      ranking = build(:keyword_ranking, tracked_keyword_country: tkc, rank: 1)
      expect(ranking).to be_valid
    end

    it "allows rank of 250" do
      ranking = build(:keyword_ranking, tracked_keyword_country: tkc, rank: 250)
      expect(ranking).to be_valid
    end

    it "allows tracked_keyword_country to be nil (preserves history on parent destroy)" do
      # The FK is intentionally nullable: TrackedKeywordCountry#destroy nullifies
      # the FK (dependent: :nullify) so users don't lose paid-for rank history
      # when they untrack a keyword. Rows with FK = nil remain queryable via
      # organization_id + keyword until the Retention job prunes them.
      ranking = build(:keyword_ranking, organization: organization, tracked_keyword_country: nil, keyword: "x")
      expect(ranking).to be_valid
    end
  end

  describe "associations" do
    it "belongs to organization" do
      ranking = create(:keyword_ranking, organization: organization, tracked_keyword_country: tkc)
      expect(ranking.organization).to eq(organization)
    end

    it "belongs to tracked_keyword_country" do
      ranking = create(:keyword_ranking, organization: organization, tracked_keyword_country: tkc)
      expect(ranking.tracked_keyword_country).to eq(tkc)
    end
  end

  describe "scopes" do
    let(:tk_tools) { create(:tracked_keyword, apple_app: apple_app, keyword: "tools") }
    let(:tk_productivity) { create(:tracked_keyword, apple_app: apple_app, keyword: "productivity") }
    let(:tkc_tools_us) { create(:tracked_keyword_country, tracked_keyword: tk_tools, country: "us") }
    let(:tkc_productivity_de) { create(:tracked_keyword_country, tracked_keyword: tk_productivity, country: "de") }

    let!(:ranking1) { create(:keyword_ranking, organization: organization, tracked_keyword_country: tkc_tools_us, keyword: "tools", rank: 5, checked_on: Date.current) }
    let!(:ranking2) { create(:keyword_ranking, organization: organization, tracked_keyword_country: tkc_productivity_de, keyword: "productivity", rank: nil, checked_on: 10.days.ago.to_date) }
    let!(:ranking3) { create(:keyword_ranking, organization: organization, tracked_keyword_country: tkc_tools_us, keyword: "tools", rank: 8, checked_on: 45.days.ago.to_date) }

    describe ".for_app" do
      it "filters by apple_app via the tracked_keyword_country -> tracked_keyword chain" do
        other_org = create(:organization)
        other_app = create(:apple_app, organization: other_org, sku: "sku-other")
        other_tk  = create(:tracked_keyword, apple_app: other_app, keyword: "other")
        other_tkc = create(:tracked_keyword_country, tracked_keyword: other_tk, country: "gb")
        create(:keyword_ranking, organization: other_org, tracked_keyword_country: other_tkc, keyword: "other", checked_on: Date.current)

        expect(KeywordRanking.for_app(apple_app)).to contain_exactly(ranking1, ranking2, ranking3)
      end
    end

    describe ".for_keyword" do
      it "filters by keyword" do
        expect(KeywordRanking.for_keyword("tools")).to contain_exactly(ranking1, ranking3)
      end
    end

    describe ".recent" do
      it "returns rankings from the last 30 days by default" do
        expect(KeywordRanking.recent).to contain_exactly(ranking1, ranking2)
      end

      it "accepts a custom number of days" do
        expect(KeywordRanking.recent(60)).to contain_exactly(ranking1, ranking2, ranking3)
      end
    end

    describe ".ranked" do
      it "excludes nil-rank records" do
        expect(KeywordRanking.ranked).to contain_exactly(ranking1, ranking3)
      end
    end

    describe ".ordered" do
      it "orders by checked_on desc" do
        expect(KeywordRanking.ordered.to_a).to eq([ ranking1, ranking2, ranking3 ])
      end
    end
  end

  # Transitional before_save hook (Phase A → B) has been removed now that the
  # legacy polymorphic columns (listable, locale) are gone from
  # keyword_rankings. The FK (tracked_keyword_country_id) is set directly.
end
