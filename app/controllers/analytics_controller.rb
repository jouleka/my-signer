class AnalyticsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org
  after_action :verify_authorized

  def index
    authorize @organization, :show?
    set_current_organization!(@organization)

    @entitlements = @organization.entitlements
    @apple_apps = @organization.apple_apps.order(:name)
    @android_apps = @organization.android_apps.order(:name)

    @allowed_analytics_days = [ 7, 14, 30, 90, 365 ].select { |d| d <= @entitlements.max_analytics_history_days }
    # If the plan's max history window is smaller than our smallest preset (e.g. an
    # artificially low custom value), fall back to the plan's own ceiling so the
    # picker still has at least one option and @days stays non-nil.
    @allowed_analytics_days = [ @entitlements.max_analytics_history_days ] if @allowed_analytics_days.empty?
    @app_filter = params[:app].presence
    @days = (params[:days].presence || 30).to_i
    @days = @allowed_analytics_days.include?(@days) ? @days : @allowed_analytics_days.last
    @tab = params[:tab].presence || "acquisition"

    load_analytics_data
  end

  # POST /organizations/:organization_id/analytics/sync
  def sync
    authorize @organization, :manage_resources?

    unless @organization.entitlements.analytics_dashboard_enabled?
      return redirect_to organization_analytics_path(@organization),
        alert: "Analytics dashboard is not available on your current plan."
    end

    AnalyticsSyncJob.perform_later(organization_id: @organization.id)

    redirect_to organization_analytics_path(@organization, days: params[:days], app: params[:app], tab: params[:tab]),
      notice: "Analytics sync started — data will update in a few minutes."
  end

  private

  def set_org
    # Scoped to caller's orgs so non-member access 404s like a missing id —
    # closes the org-id enumeration oracle. See
    # OrganizationsController#set_organization for full rationale.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def load_analytics_data
    scope = @organization.app_analytics_snapshots.last_n_days(@days)
    scope = scope.where("snapshot_date >= ?", @entitlements.max_analytics_history_days.days.ago.to_date)

    if @app_filter
      type, id = @app_filter.split("_", 2)
      if type == "apple" && id.present?
        scope = scope.where(snapshotable_type: "AppleApp", snapshotable_id: id)
      elsif type == "android" && id.present?
        scope = scope.where(snapshotable_type: "AndroidApp", snapshotable_id: id)
      end
    end

    @daily_data = scope
      .group(:snapshot_date)
      .order(:snapshot_date)
      .select(
        "snapshot_date",
        "SUM(first_time_downloads) as first_time_downloads",
        "SUM(redownloads) as redownloads",
        "SUM(total_downloads) as total_downloads",
        "SUM(impressions) as impressions",
        "SUM(product_page_views) as product_page_views",
        "SUM(updates) as updates",
        "SUM(crashes) as crashes",
        "AVG(crash_rate) as crash_rate",
        "AVG(anr_rate) as anr_rate",
        "AVG(conversion_rate) as conversion_rate",
        "SUM(installs) as installs",
        "SUM(deletions) as deletions",
        "AVG(retention_day_1) as retention_day_1",
        "AVG(retention_day_7) as retention_day_7",
        "AVG(retention_day_14) as retention_day_14",
        "AVG(retention_day_28) as retention_day_28",
        "SUM(new_subscriptions) as new_subscriptions",
        "SUM(churned_subscriptions) as churned_subscriptions",
        "SUM(trial_starts) as trial_starts",
        "SUM(trial_conversions) as trial_conversions",
        "SUM(proceeds) as proceeds"
      )

    @totals = {
      first_time_downloads: scope.sum(:first_time_downloads),
      redownloads: scope.sum(:redownloads),
      impressions: scope.sum(:impressions),
      product_page_views: scope.sum(:product_page_views),
      updates: scope.sum(:updates),
      crashes: scope.sum(:crashes),
      avg_conversion_rate: scope.where.not(conversion_rate: nil).average(:conversion_rate)&.round(1) || 0,
      avg_crash_rate: scope.where.not(crash_rate: nil).average(:crash_rate)&.round(6) || 0,
      avg_anr_rate: scope.where.not(anr_rate: nil).average(:anr_rate)&.round(6) || 0,
      installs: scope.sum(:installs),
      deletions: scope.sum(:deletions),
      avg_retention_day_1: scope.where.not(retention_day_1: nil).average(:retention_day_1)&.round(1) || 0,
      avg_retention_day_7: scope.where.not(retention_day_7: nil).average(:retention_day_7)&.round(1) || 0,
      avg_retention_day_14: scope.where.not(retention_day_14: nil).average(:retention_day_14)&.round(1) || 0,
      avg_retention_day_28: scope.where.not(retention_day_28: nil).average(:retention_day_28)&.round(1) || 0,
      new_subscriptions: scope.sum(:new_subscriptions),
      churned_subscriptions: scope.sum(:churned_subscriptions),
      trial_starts: scope.sum(:trial_starts),
      trial_conversions: scope.sum(:trial_conversions),
      total_proceeds: scope.sum(:proceeds)&.round(2) || 0
    }

    # Period comparison for % change (clamped to plan-allowed history window).
    #
    # If the plan's history window is shorter than 2 * @days (very common when
    # the user picks the highest preset), the previous period would be
    # truncated -- and silently distort the % change. Surface that to the view
    # via @prev_period_truncated so the UI can render "—" instead of a
    # misleading number. Skip the prev_scope query entirely when the clamped
    # range is empty.
    history_floor = @entitlements.max_analytics_history_days.days.ago.to_date
    prev_start_raw = (@days * 2).days.ago.to_date
    prev_end = @days.days.ago.to_date
    prev_start = [ prev_start_raw, history_floor ].max
    @prev_period_truncated = prev_start_raw < history_floor
    @prev_period_empty = prev_start >= prev_end

    prev_scope = if @prev_period_empty
      @organization.app_analytics_snapshots.none
    else
      @organization.app_analytics_snapshots.where(snapshot_date: prev_start..prev_end)
    end

    if @app_filter
      type, id = @app_filter.split("_", 2)
      if type == "apple" && id.present?
        prev_scope = prev_scope.where(snapshotable_type: "AppleApp", snapshotable_id: id)
      elsif type == "android" && id.present?
        prev_scope = prev_scope.where(snapshotable_type: "AndroidApp", snapshotable_id: id)
      end
    end

    @prev_totals = {
      first_time_downloads: prev_scope.sum(:first_time_downloads),
      redownloads: prev_scope.sum(:redownloads),
      impressions: prev_scope.sum(:impressions),
      product_page_views: prev_scope.sum(:product_page_views),
      updates: prev_scope.sum(:updates),
      crashes: prev_scope.sum(:crashes),
      avg_conversion_rate: prev_scope.where.not(conversion_rate: nil).average(:conversion_rate)&.round(1) || 0,
      avg_crash_rate: prev_scope.where.not(crash_rate: nil).average(:crash_rate)&.round(6) || 0,
      installs: prev_scope.sum(:installs),
      new_subscriptions: prev_scope.sum(:new_subscriptions),
      total_proceeds: prev_scope.sum(:proceeds)&.round(2) || 0
    }

    @last_synced_at = scope.maximum(:updated_at)
  end
end
