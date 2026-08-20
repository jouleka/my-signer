module Aso
  # Detects two degraded states in Apple Ads popularity data:
  # 1. Staleness: last refresh > 72 hours ago despite a working credential
  # 2. Collapse: >80% of refreshed values equal the max (100)
  #
  # Returns a small PORO with `.healthy?`, `.stale?`, `.collapsed?`, and
  # human-readable descriptors for the UI banner.
  #
  # Why this exists: PopularityRefreshJob writes `search_popularity_updated_at`
  # whenever Apple's API returns 200, regardless of whether the values look
  # sane. Two failure modes slip past the credential-level health check:
  #
  #   - Apple silently stops returning data (no exception, values stuck at
  #     the previous day's numbers — `last_successful?` stays true).
  #   - Apple returns degraded data with most values pinned at max (the
  #     Oct 2025 collapse pattern).
  #
  # The banner this powers tells the user "your numbers may not reflect
  # reality right now" without conflating it with an outright credential
  # failure (which still owns the "Fix connection" CTA).
  class PopularityHealth
    STALE_THRESHOLD = 72.hours
    COLLAPSE_RATIO = 0.8
    # Don't flag collapse on tiny keyword sets — with <10 keywords a
    # legitimately ad-heavy niche could trigger a false positive.
    COLLAPSE_MIN_SAMPLE = 10

    Report = Struct.new(:stale, :collapsed, :last_refresh_at, :collapse_ratio, :sample_size, keyword_init: true) do
      def healthy?
        !stale && !collapsed
      end

      def stale?
        stale
      end

      def collapsed?
        collapsed
      end
    end

    def self.for(organization:)
      new(organization: organization).report
    end

    def initialize(organization:)
      @organization = organization
    end

    def report
      return healthy_report unless credential_connected?

      Report.new(
        stale: stale?,
        collapsed: collapsed?,
        last_refresh_at: last_refresh_at,
        collapse_ratio: collapse_ratio,
        sample_size: sample_size
      )
    end

    private

    def credential_connected?
      @organization.apple_ads_credential&.last_successful?
    end

    def last_refresh_at
      return @last_refresh_at if defined?(@last_refresh_at)

      @last_refresh_at = TrackedKeyword
        .joins(:apple_app)
        .where(apple_apps: { organization_id: @organization.id })
        .where.not(search_popularity_updated_at: nil)
        .maximum(:search_popularity_updated_at)
    end

    def stale?
      return false if last_refresh_at.nil?
      last_refresh_at < STALE_THRESHOLD.ago
    end

    def sample_size
      @sample_size ||= recent_sample.size
    end

    def collapse_ratio
      @collapse_ratio ||= begin
        if sample_size.zero?
          0.0
        else
          at_max = recent_sample.count { |v| v == 100 }
          at_max.to_f / sample_size
        end
      end
    end

    def recent_sample
      @recent_sample ||= TrackedKeyword
        .joins(:apple_app)
        .where(apple_apps: { organization_id: @organization.id })
        .where.not(search_popularity: nil)
        .pluck(:search_popularity)
    end

    def collapsed?
      sample_size >= COLLAPSE_MIN_SAMPLE && collapse_ratio >= COLLAPSE_RATIO
    end

    def healthy_report
      Report.new(stale: false, collapsed: false, last_refresh_at: nil, collapse_ratio: 0.0, sample_size: 0)
    end
  end
end
