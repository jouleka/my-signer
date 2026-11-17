module Dashboard
  class AnalyticsSummary
    def initialize(organization)
      @organization = organization
    end

    def to_h
      history_days = @organization.entitlements.max_analytics_history_days
      days = [ 30, history_days ].min
      today = Date.current
      start_date = today - (days - 1)
      snapshots = @organization.app_analytics_snapshots
      current_scope = snapshots.where(snapshot_date: start_date..today)
      current = metrics(current_scope)

      # A partial previous period would create a misleading trend. Free
      # accounts have only seven days of history, so show totals without it.
      previous = if history_days >= days * 2
        metrics(snapshots.where(snapshot_date: (start_date - days)...start_date))
      else
        {}
      end

      current.merge(
        days: days,
        has_data: current_scope.exists?,
        downloads_change: pct_change(current[:downloads], previous[:downloads]),
        impressions_change: pct_change(current[:impressions], previous[:impressions]),
        crash_rate_change: pct_change(current[:crash_rate], previous[:crash_rate]),
        conversion_change: pct_change(current[:conversion_rate], previous[:conversion_rate])
      )
    end

    private

    def metrics(scope)
      {
        downloads: scope.sum(:total_downloads),
        impressions: scope.sum(:impressions),
        crash_rate: scope.average(:crash_rate)&.round(2),
        conversion_rate: scope.average(:conversion_rate)&.round(1)
      }
    end

    def pct_change(current, previous)
      return if current.nil? || previous.nil? || previous.zero?

      (((current.to_f - previous.to_f) / previous.to_f) * 100).round(1)
    end
  end
end
