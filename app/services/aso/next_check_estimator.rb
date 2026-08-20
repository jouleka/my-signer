module Aso
  # Human-readable estimate of when the next rank check will run for an org,
  # given the scheduler config (midnight UTC fan-out + 0-22h stagger) and
  # the org's tier refresh cadence (Free weekly, Pro/Team daily).
  #
  # Pure function, no side effects — call from views/controllers freely.
  # The expected completion is the scheduler run time plus half the stagger
  # window (statistical mean, since each org gets a random 0-22h delay in
  # Aso::RankCheckSchedulerJob).
  class NextCheckEstimator
    SCHEDULER_HOUR_UTC = 0 # matches config/recurring.yml "every day at 12am"
    STAGGER_MAX_HOURS = 22

    def self.for(organization:, now: Time.current)
      new(organization: organization, now: now).estimate
    end

    def initialize(organization:, now:)
      @organization = organization
      @now = now
    end

    # Returns an Estimate struct:
    #   .hours_away         → Integer, clamped to [0, 192] (8 days)
    #   .within_24h?        → Boolean
    #   .human              → "in ~14 hours" / "in under an hour" / "tomorrow" / "within the next week"
    #   .refresh_cadence    → "daily" | "weekly"
    def estimate
      cadence_days = @organization.entitlements.keyword_tracking_refresh_days
      refresh_cadence = cadence_days == 1 ? "daily" : "weekly"

      next_scheduler_at = next_scheduler_run
      # Expected completion = scheduler tick + mean of the 0-22h stagger window.
      expected_at = next_scheduler_at + (STAGGER_MAX_HOURS / 2.0).hours

      hours_away = ((expected_at - @now) / 1.hour).round.clamp(0, 24 * 8)

      Estimate.new(
        hours_away: hours_away,
        within_24h: hours_away <= 24,
        human: humanize(hours_away, cadence_days),
        refresh_cadence: refresh_cadence
      )
    end

    private

    Estimate = Struct.new(:hours_away, :within_24h, :human, :refresh_cadence, keyword_init: true) do
      def within_24h?
        within_24h
      end
    end

    def next_scheduler_run
      today_run = @now.utc.change(hour: SCHEDULER_HOUR_UTC)
      today_run > @now ? today_run : today_run + 1.day
    end

    def humanize(hours, cadence_days)
      # Free tier (weekly refresh) — vaguer window, since the first run might
      # happen tonight but the second is a week out.
      return "within the next week" if cadence_days > 1
      return "in under an hour" if hours <= 0
      return "in ~#{hours} hours" if hours.between?(1, 23)
      "tomorrow"
    end
  end
end
