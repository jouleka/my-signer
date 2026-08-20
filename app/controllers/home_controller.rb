class HomeController < ApplicationController
  before_action :authenticate_user!
  before_action :sync_organization_if_stale

  # Sync jobs that don't have a dedicated dashboard card via the
  # iOS/Android credential rows. Keep in lockstep with
  # Sync::StatusAggregator.advisory_lock_key_for -- the keys here are
  # OrgSyncRun#job_name values. Mapping a job_name to nil intentionally
  # excludes it from the dashboard "other sync errors" surface (used
  # for asc / google_play, which already render via the credential
  # cards above).
  OTHER_SYNC_JOB_DISPLAY = {
    "reviews"             => { label: "Reviews",          icon: "fa-solid fa-star" },
    "analytics"           => { label: "Analytics",        icon: "fa-solid fa-chart-line" },
    "cpp"                 => { label: "Custom product pages", icon: "fa-solid fa-layer-group" },
    "keywords_rank"       => { label: "Keyword rankings", icon: "fa-solid fa-magnifying-glass-chart" },
    "keywords_popularity" => { label: "Keyword popularity", icon: "fa-solid fa-fire" }
  }.freeze

  def index
    @organization = current_organization
    return unless @organization

    # Sync state and credentials
    @has_creds = @organization.app_store_connect_credentials.active.exists?
    @last_cred = @organization.app_store_connect_credentials.order(last_synced_at: :desc).first
    @sync_running = sync_lock_present?(@organization.id)

    @android_has_creds = @organization.google_play_credentials.active.exists?
    @android_last_cred = @organization.google_play_credentials.order(last_synced_at: :desc).first
    @android_sync_running = gp_sync_lock_present?(@organization.id)

    # API tokens (for CLI setup)
    @has_api_token = @organization.api_tokens.active.exists?

    # iOS-focused metrics
    certs_scope = AppleCertificate.where(organization_id: @organization.id)
                                  .where("platform = ? OR certificate_type IN (?)", "IOS", [ "DEVELOPMENT", "IOS_DEVELOPMENT", "IOS_DISTRIBUTION" ])
    profiles_scope = AppleProvisioningProfile.where(organization_id: @organization.id, platform: "IOS")
    devices_scope = AppleDevice.where(organization_id: @organization.id, platform: "IOS")

    @certificates_count = certs_scope.count
    @devices_count = devices_scope.count
    @profiles_count = profiles_scope.count
    @invalid_profiles_count = profiles_scope.where(state: "INVALID").count

    next_cert_expiry = certs_scope.minimum(:expires_at)
    next_profile_expiry = profiles_scope.minimum(:expires_at)

    @next_expiry_at, @next_expiry_kind = pick_earliest_with_kind(next_cert_expiry, next_profile_expiry)
    @expiring_soon = @next_expiry_at.present? && @next_expiry_at <= 30.days.from_now

    # Surface sync-job errors that the iOS/Android credential cards don't
    # cover (reviews, analytics, custom product pages, keyword rankings).
    # Without this, the navbar's unified-Sync button can fail for one of
    # these jobs and the dashboard stays blank -- which is what made the
    # toast "See details" link feel broken: the anchor target
    # (`#sync-error-alerts`) wouldn't render at all unless iOS, Android,
    # or invalid-profiles already had something to show.
    @other_sync_errors = build_other_sync_errors

    # Android metrics
    android_apps_scope = AndroidApp.where(organization_id: @organization.id)
    android_tracks_scope = AndroidTrack.joins(:android_app).where(android_apps: { organization_id: @organization.id })
    android_keystores_scope = AndroidKeystore.where(organization_id: @organization.id)
    play_store_releases_scope = PlayStoreRelease.joins(:android_app).where(android_apps: { organization_id: @organization.id })

    @android_apps_count = android_apps_scope.count
    @android_tracks_count = android_tracks_scope.count
    @android_active_tracks_count = android_tracks_scope.where(status: "active").count
    @android_keystores_count = android_keystores_scope.count
    @android_active_keystores_count = android_keystores_scope.active.count
    @play_store_releases_count = play_store_releases_scope.count
    # Phase 5: Dashboard content
    load_dashboard_data(certs_scope, profiles_scope)
  end

  private

  def sync_organization_if_stale
    sync_if_stale(current_organization)
  end

  # Reads OrgSyncRun rows via Sync::StatusAggregator (same source the
  # navbar's sync polling reads) and returns one error entry per failed
  # job that isn't already covered by the iOS/Android credential cards.
  # Dedupes on label as a defensive measure against future name aliases
  # mapping to the same display row.
  def build_other_sync_errors
    payload = Sync::StatusAggregator.new(organization: @organization).payload
    jobs = payload[:jobs] || {}
    seen_labels = Set.new
    errors = []

    jobs.each do |name, info|
      next unless info[:status].to_s == "error"
      display = OTHER_SYNC_JOB_DISPLAY[name.to_s]
      next unless display
      next if seen_labels.include?(display[:label])

      seen_labels << display[:label]
      message = info[:error_message].presence || "Sync failed"
      errors << {
        key: name.to_s,
        label: display[:label],
        icon: display[:icon],
        error_message: message,
        hint: helpers.sync_error_hint(message)
      }
    end

    errors
  end

  def pick_earliest_with_kind(cert_at, profile_at)
    if cert_at.present? && profile_at.present?
      cert_at <= profile_at ? [ cert_at, :certificate ] : [ profile_at, :profile ]
    elsif cert_at.present?
      [ cert_at, :certificate ]
    elsif profile_at.present?
      [ profile_at, :profile ]
    else
      [ nil, nil ]
    end
  end

  def load_dashboard_data(certs_scope, profiles_scope)
    @entitlements = @organization.entitlements

    # 1. Release status cards
    #
    # Avoid loading every version/release into Ruby just to find the most recent
    # per-app row (quadratic for orgs with many apps and many versions per app).
    # Use Postgres DISTINCT ON to fetch the single newest row per parent_id in
    # one query, then look it up by id inside the loop.
    # Materialize the relations once (.to_a) -- otherwise `pluck(:id)` and the
    # later `.map` each issue a separate SELECT against the same table.
    apple_apps = @organization.apple_apps.order(:name).to_a
    android_apps = @organization.android_apps.order(:name).to_a

    apple_app_ids = apple_apps.map(&:id)
    android_app_ids = android_apps.map(&:id)

    latest_apple_versions = if apple_app_ids.any?
      AppStoreVersion
        .where(apple_app_id: apple_app_ids)
        .order(:apple_app_id, created_at: :desc)
        .select("DISTINCT ON (apple_app_id) *")
        .index_by(&:apple_app_id)
    else
      {}
    end

    latest_play_releases = if android_app_ids.any?
      # Order by released_at first (matches the original max_by precedence:
      # released_at if present, otherwise created_at), then created_at as tiebreaker.
      # NULLS LAST keeps unreleased rows behind released ones.
      PlayStoreRelease
        .where(android_app_id: android_app_ids)
        .order(:android_app_id)
        .order(Arel.sql("released_at DESC NULLS LAST"))
        .order(created_at: :desc)
        .select("DISTINCT ON (android_app_id) *")
        .index_by(&:android_app_id)
    else
      {}
    end

    ios_items = apple_apps.map do |app|
      latest = latest_apple_versions[app.id]
      {
        app_id: app.id,
        platform: :ios,
        name: app.name.presence || app.bundle_id,
        version: latest&.version_string,
        computed_status: latest ? computed_status_for_asv(latest) : "unknown",
        path: organization_release_path(@organization, "apple_app_#{app.id}")
      }
    end

    android_items = android_apps.map do |app|
      latest = latest_play_releases[app.id]
      {
        app_id: app.id,
        platform: :android,
        name: app.name.presence || app.package_name,
        version: latest&.version_code,
        computed_status: latest&.status || "unknown",
        track: latest&.track,
        user_fraction: latest&.user_fraction,
        path: organization_release_path(@organization, "android_app_#{app.id}")
      }
    end

    @release_status_items = ios_items + android_items

    # 2. Rating snapshot
    apple_snap = @organization.rating_snapshots
                              .where(snapshotable_type: "AppleApp")
                              .order(snapshot_date: :desc).first
    android_snap = @organization.rating_snapshots
                                .where(snapshotable_type: "AndroidApp")
                                .order(snapshot_date: :desc).first

    apple_prev = apple_snap ? @organization.rating_snapshots
                                .where(snapshotable_type: "AppleApp")
                                .where("snapshot_date < ?", apple_snap.snapshot_date)
                                .order(snapshot_date: :desc).first
                             : nil
    android_prev = android_snap ? @organization.rating_snapshots
                                   .where(snapshotable_type: "AndroidApp")
                                   .where("snapshot_date < ?", android_snap.snapshot_date)
                                   .order(snapshot_date: :desc).first
                                : nil

    @rating_data = {
      apple_rating: apple_snap&.average_rating,
      apple_review_count: apple_snap&.review_count,
      apple_trend: trend_direction(apple_snap&.average_rating, apple_prev&.average_rating),
      android_rating: android_snap&.average_rating,
      android_review_count: android_snap&.review_count,
      android_trend: trend_direction(android_snap&.average_rating, android_prev&.average_rating)
    }

    # 3. Recent reviews
    @recent_reviews = @organization.app_reviews.includes(:reviewable).order(reviewed_at: :desc).limit(5)

    # 4. Expiring assets (certs + profiles + keystores, next 30 days)
    expiring_certs = certs_scope.expiring_within(30).order(:expires_at)
    expiring_profiles = profiles_scope.expiring_within(30).order(:expires_at)
    expiring_keystores = AndroidKeystore.where(organization_id: @organization.id).expiring_within(30).order(:expires_at)

    @expiring_assets = []
    expiring_certs.each do |cert|
      @expiring_assets << {
        kind: :certificate,
        name: cert.name.presence || cert.serial_number.to_s.truncate(20),
        expires_at: cert.expires_at,
        days_remaining: (cert.expires_at.to_date - Date.current).to_i,
        path: organization_apple_certificates_path(@organization)
      }
    end
    expiring_profiles.each do |profile|
      @expiring_assets << {
        kind: :profile,
        name: profile.name.presence || profile.uuid.to_s.truncate(20),
        expires_at: profile.expires_at,
        days_remaining: (profile.expires_at.to_date - Date.current).to_i,
        path: organization_apple_provisioning_profiles_path(@organization)
      }
    end
    expiring_keystores.each do |ks|
      @expiring_assets << {
        kind: :keystore,
        name: ks.name,
        expires_at: ks.expires_at,
        days_remaining: ks.days_until_expiry,
        path: organization_android_keystores_path(@organization)
      }
    end
    # Float::INFINITY (rather than a magic number like 999) makes it explicit
    # that nil values sort to the end. 999 also collides with the entitlement
    # "unlimited" sentinel elsewhere in the codebase, which would confuse a
    # future reader scanning for related constants.
    @expiring_assets.sort_by! { |a| a[:days_remaining] || Float::INFINITY }

    # 5. Screenshot studio count
    @screenshot_projects_count = @organization.screenshot_projects.count

    # 6. Analytics overview (last 30 days vs previous 30 days)
    analytics_scope = @organization.app_analytics_snapshots.last_n_days(30)
    prev_analytics_scope = @organization.app_analytics_snapshots
      .where(snapshot_date: 60.days.ago.to_date..30.days.ago.to_date)

    current_downloads = analytics_scope.sum(:total_downloads)
    prev_downloads = prev_analytics_scope.sum(:total_downloads)
    current_impressions = analytics_scope.sum(:impressions)
    prev_impressions = prev_analytics_scope.sum(:impressions)
    current_crash_rate = analytics_scope.where.not(crash_rate: nil).average(:crash_rate)&.round(2)
    prev_crash_rate = prev_analytics_scope.where.not(crash_rate: nil).average(:crash_rate)&.round(2)
    current_conversion = analytics_scope.where.not(conversion_rate: nil).average(:conversion_rate)&.round(1)
    prev_conversion = prev_analytics_scope.where.not(conversion_rate: nil).average(:conversion_rate)&.round(1)

    @analytics_data = {
      downloads: current_downloads,
      downloads_trend: trend_direction(current_downloads, prev_downloads),
      downloads_change: pct_change(current_downloads, prev_downloads),
      impressions: current_impressions,
      impressions_trend: trend_direction(current_impressions, prev_impressions),
      impressions_change: pct_change(current_impressions, prev_impressions),
      crash_rate: current_crash_rate,
      crash_rate_trend: trend_direction(prev_crash_rate, current_crash_rate), # Inverted: lower is better
      crash_rate_change: pct_change(current_crash_rate, prev_crash_rate),
      conversion_rate: current_conversion,
      conversion_trend: trend_direction(current_conversion, prev_conversion),
      conversion_change: pct_change(current_conversion, prev_conversion),
      has_data: analytics_scope.exists?
    }
  end

  def computed_status_for_asv(version)
    case version.app_store_state
    when "READY_FOR_SALE", "READY_FOR_DISTRIBUTION" then "live"
    when "IN_REVIEW", "WAITING_FOR_REVIEW", "PENDING_APPLE_RELEASE",
         "PROCESSING_FOR_DISTRIBUTION", "PENDING_DEVELOPER_RELEASE" then "in_review"
    when "REJECTED", "METADATA_REJECTED", "DEVELOPER_REJECTED", "INVALID_BINARY" then "rejected"
    else "draft"
    end
  end

  def trend_direction(current, previous)
    return :stable if current.nil? || previous.nil?
    diff = current.to_f - previous.to_f
    return :stable if diff.abs < 0.05
    diff > 0 ? :up : :down
  end

  def pct_change(current, previous)
    return nil if current.nil? || previous.nil? || previous.to_f.zero?
    (((current.to_f - previous.to_f) / previous.to_f) * 100).round(1)
  end
end
