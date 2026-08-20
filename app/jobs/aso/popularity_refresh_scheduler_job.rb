module Aso
  # Daily fan-out for Apple Ads Search Popularity refreshes. Runs at 2am UTC
  # (wired in config/recurring.yml) and enqueues one Aso::PopularityRefreshJob
  # per org that has a working Apple Ads credential (i.e. at least one prior
  # successful auth). Orgs without a credential, or with a credential that has
  # never been successful (still-broken setup), are skipped — the job itself
  # also guards on `credential&.last_successful?` but filtering here keeps the
  # queue tidy.
  #
  # The 20h stagger window is narrower than the rank-check scheduler's (22h)
  # because Apple Ads isn't rate-throttled the same way MZStore is — we
  # mainly spread to avoid a thundering herd at 2am.
  class PopularityRefreshSchedulerJob < ApplicationJob
    queue_as :default

    STAGGER_WINDOW = 20.hours

    def perform
      # Filter to orgs with a credential that has been successful at least
      # once. Orgs without a credential, or with a still-broken setup, are
      # skipped — Aso::PopularityRefreshJob double-checks this too.
      Organization
        .joins(:apple_ads_credential)
        .where.not(apple_ads_credentials: { last_successful_at: nil })
        .find_each do |org|
        delay = rand(0..STAGGER_WINDOW.to_i).seconds
        Aso::PopularityRefreshJob.set(wait: delay).perform_later(organization_id: org.id)
      end
    end
  end
end
