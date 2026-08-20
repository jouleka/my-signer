require "rails_helper"

RSpec.describe Aso::RankMovement do
  let(:org) { create(:organization) }
  let(:app) { create(:apple_app, organization: org) }
  let(:tk)  { create(:tracked_keyword, apple_app: app, keyword: "photo editor") }
  let(:tkc) { create(:tracked_keyword_country, tracked_keyword: tk, country: "us", current_rank: current_rank) }

  def seed_ranking(rank, days_ago)
    KeywordRanking.create!(
      organization: org,
      tracked_keyword_country: tkc,
      keyword: tk.keyword,
      rank: rank,
      checked_on: days_ago.days.ago.to_date
    )
  end

  describe ".for" do
    context "current rank in top 10, was in top 50" do
      let(:current_rank) { 8 }
      before { seed_ranking(35, 7) }

      it "is significant (crossed top 10)" do
        movement = described_class.for(tkc, window_days: 7)
        expect(movement).to be_significant
      end
    end

    context "current rank outside top 50, was in top 50" do
      let(:current_rank) { 55 }
      before { seed_ranking(40, 7) }

      it "is significant (crossed top 50, dropped out)" do
        movement = described_class.for(tkc, window_days: 7)
        expect(movement).to be_significant
      end
    end

    context "current rank 20, week ago was 22 (within top 100, small move)" do
      let(:current_rank) { 20 }
      before { seed_ranking(22, 7) }

      it "is NOT significant (small delta)" do
        movement = described_class.for(tkc, window_days: 7)
        expect(movement).not_to be_significant
      end
    end

    context "current rank 20, week ago was 35 (within top 100, large move)" do
      let(:current_rank) { 20 }
      before { seed_ranking(35, 7) }

      it "is significant (within top-100 and moved >5)" do
        movement = described_class.for(tkc, window_days: 7)
        expect(movement).to be_significant
      end
    end

    context "no historical ranking" do
      let(:current_rank) { 10 }

      it "returns nil" do
        expect(described_class.for(tkc, window_days: 7)).to be_nil
      end
    end

    context "tkc has no current_rank" do
      let(:current_rank) { nil }
      before { seed_ranking(5, 7) }

      it "is significant (left top 10)" do
        movement = described_class.for(tkc, window_days: 7)
        expect(movement).to be_significant
      end
    end
  end

  describe ".for_many" do
    let(:current_rank) { 8 }

    it "resolves baselines for many tkcs and matches .for, picking the newest on-or-before cutoff" do
      # tkc1 (the `let`) has two historical rows; the newer one (5 days ago)
      # is past the 7-day cutoff, so the 8-days-ago row (rank 35) is the baseline.
      seed_ranking(35, 8)
      seed_ranking(12, 5)

      tk2  = create(:tracked_keyword, apple_app: app, keyword: "video editor")
      tkc2 = create(:tracked_keyword_country, tracked_keyword: tk2, country: "us", current_rank: 60)
      KeywordRanking.create!(organization: org, tracked_keyword_country: tkc2, keyword: tk2.keyword, rank: 40, checked_on: 7.days.ago.to_date)

      # tkc3 has no qualifying history → excluded.
      tk3  = create(:tracked_keyword, apple_app: app, keyword: "audio editor")
      tkc3 = create(:tracked_keyword_country, tracked_keyword: tk3, country: "us", current_rank: 3)

      movements = described_class.for_many([ tkc, tkc2, tkc3 ], window_days: 7)

      by_tkc = movements.index_by(&:tkc)
      expect(by_tkc.keys).to match_array([ tkc, tkc2 ])
      expect(by_tkc[tkc].week_ago).to eq(35) # newest on-or-before 7-day cutoff
      expect(by_tkc[tkc].current).to eq(8)
      expect(by_tkc[tkc2].week_ago).to eq(40)
      expect(by_tkc[tkc]).to be_significant
      expect(by_tkc[tkc2]).to be_significant
    end

    it "returns [] for an empty collection without querying" do
      expect(described_class.for_many([], window_days: 7)).to eq([])
    end
  end

  describe "#delta" do
    let(:current_rank) { 10 }
    before { seed_ranking(25, 7) }

    it "is positive for upward movement (rank decreased)" do
      movement = described_class.for(tkc, window_days: 7)
      expect(movement.delta).to eq(15) # 25 -> 10 = +15 improvement
    end
  end
end
