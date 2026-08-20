module Aso
  # Plain-old Ruby object that captures a keyword ranking's current-vs-historical
  # delta for a single TrackedKeywordCountry. Used by Aso::RankAlertDigestJob to
  # decide which movements are "significant" enough to surface in the weekly
  # Team-tier digest email.
  #
  # Significance rules (any one triggers):
  #   - Crossed the top-10 threshold in either direction
  #   - Crossed the top-50 threshold in either direction
  #   - Both current and historical ranks sit within top-100 and the delta is > 5
  #
  # Nil-handling:
  #   - If both current_rank and historical rank are missing, .for returns nil
  #     (no useful movement to report).
  #   - If only one side is present, crossing a threshold still counts (e.g.
  #     current_rank = nil but last week's rank was #5 means the app dropped
  #     out of the top 10).
  class RankMovement
    attr_reader :tkc, :current, :week_ago

    # Returns a RankMovement when we have a historical baseline to compare
    # against, nil otherwise. A current rank without history can't produce a
    # meaningful "changed this week" signal — the keyword may have just been
    # added to tracking, which is a different notification concern.
    #
    # The historical lookup pulls the most recent ranking on or before
    # `window_days` ago, which lines up with the weekly digest cadence even if
    # the per-tkc check frequency is sparser than daily.
    def self.for(tkc, window_days:)
      ranking = tkc.keyword_rankings
                   .where("checked_on <= ?", window_days.days.ago.to_date)
                   .order(checked_on: :desc)
                   .first
      return nil if ranking.nil?

      new(tkc: tkc, current: tkc.current_rank, week_ago: ranking.rank)
    end

    # Batched variant of `.for` for a collection of TrackedKeywordCountry
    # records. Resolves every historical baseline in a single query (instead of
    # one query per tkc) and returns the array of RankMovements that have a
    # baseline — order is not guaranteed. Used by Aso::RankAlertDigestJob to
    # kill the per-tkc N+1.
    def self.for_many(tkcs, window_days:)
      tkcs = tkcs.to_a
      return [] if tkcs.empty?

      cutoff = window_days.days.ago.to_date
      tkc_ids = tkcs.map(&:id)

      # Most-recent-on-or-before-cutoff ranking per tkc. We pull the candidate
      # rows ordered newest-first and keep the first one seen per tkc id.
      week_ago_by_tkc = {}
      KeywordRanking
        .where(tracked_keyword_country_id: tkc_ids)
        .where("checked_on <= ?", cutoff)
        .order(checked_on: :desc)
        .pluck(:tracked_keyword_country_id, :rank)
        .each do |tkc_id, rank|
          # Keep only the newest (first-seen, since ordered desc) row per tkc,
          # mirroring `.for`'s `.order(checked_on: :desc).first` — even when that
          # newest row's rank is nil.
          week_ago_by_tkc[tkc_id] = rank unless week_ago_by_tkc.key?(tkc_id)
        end

      tkcs.filter_map do |tkc|
        next unless week_ago_by_tkc.key?(tkc.id)

        new(tkc: tkc, current: tkc.current_rank, week_ago: week_ago_by_tkc[tkc.id])
      end
    end

    def initialize(tkc:, current:, week_ago:)
      @tkc = tkc
      @current = current
      @week_ago = week_ago
    end

    # Positive delta = improvement (rank number decreased).
    # Negative delta = regression (rank number increased).
    # Nil when either side is missing — callers should treat that as "no delta".
    def delta
      return nil if current.nil? || week_ago.nil?

      week_ago - current
    end

    def significant?
      crossed_threshold?(10) || crossed_threshold?(50) || within_top_100_moved_over_5?
    end

    private

    # True when the app either entered or left the top-N bucket between the
    # historical snapshot and the current rank.
    def crossed_threshold?(n)
      entered = current && current <= n && (week_ago.nil? || week_ago > n)
      left    = week_ago && week_ago <= n && (current.nil? || current > n)
      entered || left
    end

    def within_top_100_moved_over_5?
      return false if current.nil? || week_ago.nil?

      current.between?(1, 100) && week_ago.between?(1, 100) && (current - week_ago).abs > 5
    end
  end
end
