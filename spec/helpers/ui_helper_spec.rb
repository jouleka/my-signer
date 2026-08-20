require "rails_helper"

RSpec.describe UiHelper, type: :helper do
  describe "#rank_display" do
    it "shows 'Queued' state when the keyword has never been checked" do
      html = helper.rank_display(nil, last_checked_at: nil)
      expect(html).to include("Queued")
      expect(html).not_to include("Not in top 250")
      expect(html).to include("Next refresh runs nightly")
    end

    it "shows rank position with tooltip when rank is present" do
      html = helper.rank_display(12, last_checked_at: 1.hour.ago)
      expect(html).to include("#12")
      expect(html).to include("Last checked")
    end

    it "shows 'Not in top 250' when checked but no rank was returned" do
      html = helper.rank_display(nil, last_checked_at: 1.hour.ago)
      expect(html).to include("Not in top 250")
      expect(html).not_to include("Queued")
      # Explanatory tooltip so users know a check actually ran.
      expect(html).to include("Apple")
    end

    it "renders a rank without a tooltip when last_checked_at is nil" do
      html = helper.rank_display(7, last_checked_at: nil)
      expect(html).to include("#7")
      # No 'Last checked ... ago' tooltip when we don't know when.
      expect(html).not_to include("Last checked")
    end

    it "uses the estimator's human ETA in the Queued tooltip when passed" do
      estimate = Aso::NextCheckEstimator::Estimate.new(
        hours_away: 14, within_24h: true, human: "in ~14 hours", refresh_cadence: "daily"
      )
      html = helper.rank_display(nil, last_checked_at: nil, estimate: estimate)
      expect(html).to include("First result in ~14 hours")
      expect(html).to include("refreshes daily")
      # The fallback copy should be suppressed when a real estimate is provided.
      expect(html).not_to include("Next refresh runs nightly")
    end
  end
end
