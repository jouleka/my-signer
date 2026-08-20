module Aso
  # Nightly fan-out. Runs once at midnight UTC (wired in config/recurring.yml)
  # and enqueues one Aso::KeywordRankCheckJob per org that has at least one
  # enabled tracked keyword/country pair. Each enqueue gets a random `wait:`
  # between 0 and 22 hours so the outbound MZStore traffic is smeared across
  # the day — combined with Aso::RateLimiter (15 req/min) and the single-thread
  # aso_scraping worker block in config/queue.yml, this keeps us well below
  # Apple's implicit throttle.
  #
  # Team-tier orgs go to :aso_scraping_priority so their work is drained before
  # Free/Pro traffic when the queue is backed up.
  class RankCheckSchedulerJob < ApplicationJob
    queue_as :default

    # Spread of org-level enqueues across the day. 22h leaves a 2h tail before
    # the next midnight scheduler tick so jobs that miss their slot (e.g. from
    # an exhausted rate-limiter retry) still have headroom to complete.
    STAGGER_WINDOW = 22.hours

    def perform
      # Fan out to any org with at least one enabled tracked keyword/country
      # pair. The per-job handler does the plan-tier check; keeping the scope
      # permissive here means a mid-sync owner downgrade doesn't silently
      # strand keyword refreshes.
      Organization
        .joins(apple_apps: { tracked_keywords: :tracked_keyword_countries })
        .where(tracked_keywords: { enabled: true })
        .where(tracked_keyword_countries: { enabled: true })
        .distinct
        .find_each do |org|
        queue = org.entitlements.keyword_tracking_priority_queue? ? :aso_scraping_priority : :aso_scraping
        delay = rand(0..STAGGER_WINDOW.to_i).seconds
        Aso::KeywordRankCheckJob.set(queue: queue, wait: delay).perform_later(organization_id: org.id)
      end
    end
  end
end
