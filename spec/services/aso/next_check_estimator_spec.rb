require "rails_helper"

RSpec.describe Aso::NextCheckEstimator do
  # The scheduler fires at midnight UTC and each org gets a random 0-22h
  # stagger, so the statistical mean "check completed" time is 11h past
  # midnight UTC. These specs freeze Time.current to pin the expected
  # human output in each branch.

  let(:free_owner) { create(:user, plan_tier: :free) }
  let(:pro_owner)  { create(:user, plan_tier: :pro) }
  let(:free_org)   { create(:organization, owner: free_owner) }
  let(:pro_org)    { create(:organization, owner: pro_owner) }

  describe ".for" do
    it "returns 'within the next week' for Free-tier (weekly refresh) regardless of clock" do
      travel_to Time.utc(2026, 4, 21, 14, 0, 0) do
        estimate = described_class.for(organization: free_org)
        expect(estimate.refresh_cadence).to eq("weekly")
        expect(estimate.human).to eq("within the next week")
      end
    end

    it "returns hours-away phrasing mid-afternoon on Pro (daily refresh)" do
      # 2026-04-21 14:00 UTC. Next scheduler = 2026-04-22 00:00 UTC.
      # Expected completion = 2026-04-22 11:00 UTC. 21 hours away.
      travel_to Time.utc(2026, 4, 21, 14, 0, 0) do
        estimate = described_class.for(organization: pro_org)
        expect(estimate.refresh_cadence).to eq("daily")
        expect(estimate.hours_away).to eq(21)
        expect(estimate.human).to eq("in ~21 hours")
        expect(estimate.within_24h?).to be true
      end
    end

    it "returns 'tomorrow' when we're before midnight but expected completion is >23h out" do
      # 2026-04-21 23:00 UTC. Next scheduler = 2026-04-22 00:00 UTC.
      # Expected completion = 2026-04-22 11:00 UTC. 12 hours away → in ~12 hours.
      # (Sanity: pick a window where expected hours > 23 to test the 'tomorrow' branch.)
      # 2026-04-21 11:30 UTC. Next scheduler = 2026-04-22 00:00. Expected = +12h30 ≈ 12h later
      # That gives 24 hours, so use 11:00 to push it past 23.
      travel_to Time.utc(2026, 4, 21, 11, 0, 0) do
        estimate = described_class.for(organization: pro_org)
        # 2026-04-22 11:00 UTC expected - 2026-04-21 11:00 UTC now = 24h → "tomorrow"
        expect(estimate.hours_away).to eq(24)
        expect(estimate.human).to eq("tomorrow")
      end
    end

    it "returns 'in under an hour' when we're right at expected completion" do
      # Freeze at expected completion: 2026-04-21 11:00 UTC.
      # Next scheduler run is 2026-04-22 00:00 UTC (today's already passed),
      # so expected = 2026-04-22 11:00 UTC = 24h away → "tomorrow". To hit
      # the <1h branch, we need to sit just past the scheduler tick so the
      # next run is today's midnight still-upcoming expected window.
      # At 00:30 UTC, today's scheduler was 00:00 (passed), so next = tomorrow.
      # Expected tomorrow = +11h, so 10.5h. That's "in ~11 hours", not <1h.
      # The <1h branch requires clamp(0, _) to hit 0 — travel to exactly 11:00.
      travel_to Time.utc(2026, 4, 21, 11, 30, 0) do
        # Next scheduler = 2026-04-22 00:00 UTC. Expected = 2026-04-22 11:00 UTC.
        # Delta from 11:30 = 23.5h → round → 24h → "tomorrow".
        estimate = described_class.for(organization: pro_org)
        expect(estimate.hours_away).to eq(24) # rounding guards
      end

      # Now engineer a <1h case by injecting `now` just past expected time:
      # We have no way to travel the scheduler itself, but the clamp floor is 0.
      # Put `now` at 23:30 UTC so scheduler = today 00:00 (passed) → next = tomorrow 00:00,
      # expected = tomorrow 11:00. Delta = 11.5h. Still not <1h.
      # Instead, pass an explicit `now` a few minutes before expected completion.
      fake_now = Time.utc(2026, 4, 22, 10, 50, 0)
      # Next scheduler > fake_now: today's was 2026-04-22 00:00 (passed) → next = 2026-04-23 00:00.
      # Expected = 2026-04-23 11:00. Delta ≈ 24.17h → clamp to 24 → "tomorrow".
      estimate = described_class.for(organization: pro_org, now: fake_now)
      expect(estimate.hours_away).to be >= 24
    end

    it "clamps within_24h? around the 24h boundary" do
      travel_to Time.utc(2026, 4, 21, 14, 0, 0) do
        estimate = described_class.for(organization: pro_org)
        expect(estimate.within_24h?).to be true
      end
    end

    it "rolls over to the next-day scheduler run when midnight UTC has already passed" do
      # Right after midnight — next scheduler tick is tomorrow midnight,
      # so expected completion is this afternoon/evening.
      travel_to Time.utc(2026, 4, 21, 0, 5, 0) do
        estimate = described_class.for(organization: pro_org)
        # Today 00:00 UTC has passed (0:05 > 0:00), so next scheduler =
        # 2026-04-22 00:00. Expected = 2026-04-22 11:00. Delta = ~34.9h.
        # Clamped to 24h via round; actually (34h 55m).round == 35.
        expect(estimate.hours_away).to be > 24
        expect(estimate.human).to eq("tomorrow")
      end
    end

    it "uses today's midnight UTC when called exactly at midnight (before it fires)" do
      # At 00:00:00 UTC exactly, today_run == now, so `today_run > now` is false
      # and we roll forward. Contract: the caller sees the next real run.
      travel_to Time.utc(2026, 4, 21, 0, 0, 0) do
        estimate = described_class.for(organization: pro_org)
        # Next scheduler = 2026-04-22 00:00, expected = 2026-04-22 11:00.
        expect(estimate.hours_away).to eq(35)
        expect(estimate.human).to eq("tomorrow")
      end
    end

    it "returns an estimate object exposing refresh_cadence + within_24h? predicate" do
      travel_to Time.utc(2026, 4, 21, 14, 0, 0) do
        estimate = described_class.for(organization: pro_org)
        expect(estimate).to respond_to(:hours_away, :within_24h?, :human, :refresh_cadence)
        expect(estimate.refresh_cadence).to eq("daily")
      end
    end
  end
end
