class AnalyticsSyncJob < ApplicationJob
  include AdvisoryLockable
  include SyncRunTrackable

  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(organization_id:)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    with_advisory_lock("analytics:sync:org:#{organization.id}") do
      track_sync_run(organization: organization, job_name: :analytics) do
        entitlements = organization.entitlements
        next unless entitlements.analytics_dashboard_enabled?

        sync_apple_analytics(organization)
        sync_google_vitals(organization)
      end
    end
  end

  private

  def sync_apple_analytics(organization)
    credential = organization.app_store_connect_credentials.find_by(active: true)
    return unless credential

    # Previously: each Apple app did 5 sequential report downloads (each is
    # metadata GET + segment list + gzip TSV download). For N apps this was
    # ~25–30 HTTPS calls strictly serial — the dominant contributor to the
    # 30-second wall-clock. Fan out per-app: every future builds its own
    # Client (Faraday Net::HTTP adapter isn't safe to share across threads).
    apps = organization.apple_apps.to_a
    ::Sync::ParallelFanout.call(apps) do |apple_app|
      client = AppStoreConnect::Client.new(credential: credential)
      analytics = AppStoreConnect::AnalyticsReports.new(client)
      ::Sync::Timings.measure("analytics.apple_app", org: organization.id, app: apple_app.id) do
        sync_apple_app_analytics(organization, apple_app, analytics)
      end
    rescue StandardError => e
      Rails.logger.warn("AnalyticsSyncJob: Apple analytics failed for #{apple_app.name}: #{e.message}")
    end
  end

  def sync_apple_app_analytics(organization, apple_app, analytics)
    downloads_data = analytics.fetch_latest_report_data(
      app_id: apple_app.app_store_id,
      category: "COMMERCE",
      report_name: "Downloads"
    )

    engagement_data = analytics.fetch_latest_report_data(
      app_id: apple_app.app_store_id,
      category: "APP_STORE_ENGAGEMENT",
      report_name: "Discovery and Engagement"
    )

    crashes_data = analytics.fetch_latest_report_data(
      app_id: apple_app.app_store_id,
      category: "APP_USAGE",
      report_name: "Crashes"
    )

    installs_data = analytics.fetch_latest_report_data(
      app_id: apple_app.app_store_id,
      category: "APP_USAGE",
      report_name: "Installations and Deletions"
    )

    subscription_data = analytics.fetch_latest_report_data(
      app_id: apple_app.app_store_id,
      category: "COMMERCE",
      report_name: "Subscription"
    )

    by_date = {}

    downloads_data.each do |row|
      date = row["Date"]
      next unless date
      by_date[date] ||= { first_time_downloads: 0, redownloads: 0, updates: 0 }
      dl_type = row["Download Type"] || row["Event Type"]
      count = row["Counts"]&.to_i || row["Total Downloads"]&.to_i || 0

      case dl_type
      when /first.time/i then by_date[date][:first_time_downloads] += count
      when /redownload/i then by_date[date][:redownloads] += count
      when /update/i then by_date[date][:updates] += count
      end
    end

    engagement_data.each do |row|
      date = row["Date"]
      next unless date
      by_date[date] ||= {}
      impressions = row["Impressions"]&.to_i || row["Counts"]&.to_i || 0
      page_views = row["Product Page Views"]&.to_i || row["Page Views"]&.to_i || 0
      by_date[date][:impressions] = (by_date[date][:impressions] || 0) + impressions
      by_date[date][:product_page_views] = (by_date[date][:product_page_views] || 0) + page_views
    end

    crashes_data.each do |row|
      date = row["Date"]
      next unless date
      by_date[date] ||= {}
      by_date[date][:crashes] = (by_date[date][:crashes] || 0) + (row["Crashes"]&.to_i || row["Counts"]&.to_i || 0)
    end

    installs_data.each do |row|
      date = row["Date"]
      next unless date
      by_date[date] ||= {}
      by_date[date][:installs] = (by_date[date][:installs] || 0) + (row["Installations"]&.to_i || row["Installs"]&.to_i || 0)
      by_date[date][:deletions] = (by_date[date][:deletions] || 0) + (row["Deletions"]&.to_i || 0)
    end

    subscription_data.each do |row|
      date = row["Date"]
      next unless date
      by_date[date] ||= {}
      event_type = row["Event"] || row["Subscription Event"] || ""
      count = row["Counts"]&.to_i || row["Events"]&.to_i || 0

      case event_type
      when /new subscription|subscribe/i
        by_date[date][:new_subscriptions] = (by_date[date][:new_subscriptions] || 0) + count
      when /cancel|churn/i
        by_date[date][:churned_subscriptions] = (by_date[date][:churned_subscriptions] || 0) + count
      when /trial start|free trial/i
        by_date[date][:trial_starts] = (by_date[date][:trial_starts] || 0) + count
      when /trial conversion|convert/i
        by_date[date][:trial_conversions] = (by_date[date][:trial_conversions] || 0) + count
      end

      if row["Proceeds"].present?
        by_date[date][:proceeds] = (by_date[date][:proceeds] || 0) + row["Proceeds"].to_f
      end
    end

    snapshots = by_date.map do |date_str, metrics|
      total_dl = metrics[:first_time_downloads].to_i + metrics[:redownloads].to_i
      {
        organization_id: organization.id,
        snapshotable_type: "AppleApp",
        snapshotable_id: apple_app.id,
        snapshot_date: Date.strptime(date_str, "%Y-%m-%d"),
        first_time_downloads: metrics[:first_time_downloads] || 0,
        redownloads: metrics[:redownloads] || 0,
        total_downloads: total_dl,
        impressions: metrics[:impressions] || 0,
        product_page_views: metrics[:product_page_views] || 0,
        updates: metrics[:updates] || 0,
        conversion_rate: metrics[:impressions].to_i > 0 ? (total_dl.to_f / metrics[:impressions] * 100).round(2) : nil,
        crashes: metrics[:crashes] || 0,
        installs: metrics[:installs] || 0,
        deletions: metrics[:deletions] || 0,
        new_subscriptions: metrics[:new_subscriptions] || 0,
        churned_subscriptions: metrics[:churned_subscriptions] || 0,
        trial_starts: metrics[:trial_starts] || 0,
        trial_conversions: metrics[:trial_conversions] || 0,
        proceeds: metrics[:proceeds],
        data_source: "apple_analytics",
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    if snapshots.any?
      AppAnalyticsSnapshot.upsert_all(snapshots,
        unique_by: %i[snapshotable_type snapshotable_id snapshot_date])
    end

    Rails.logger.info("AnalyticsSyncJob: Synced #{snapshots.size} Apple analytics snapshots for #{apple_app.name}")
  end

  def sync_google_vitals(organization)
    credential = organization.google_play_credentials.find_by(active: true)
    return unless credential

    apps = organization.android_apps.to_a
    # Thread-safe flags that collect signal from every future. After the
    # fan-out we read them on the main thread and update the credential
    # exactly once — avoids one-UPDATE-per-app write amplification and
    # avoids thread races writing the same column.
    api_disabled = Concurrent::AtomicBoolean.new(false)
    any_success  = Concurrent::AtomicBoolean.new(false)

    # Fan out per-app. Each future builds its own GooglePlay::Vitals
    # instance for thread isolation (the googleauth library shares token
    # state, but building per-thread is cheap and avoids surprises).
    ::Sync::ParallelFanout.call(apps) do |android_app|
      begin
        vitals = GooglePlay::Vitals.new(credential: credential)
      rescue StandardError => e
        Rails.logger.warn("AnalyticsSyncJob: Google Vitals init failed for #{android_app.name}: #{e.message}")
        next
      end
      begin
        ::Sync::Timings.measure("analytics.android_app", org: organization.id, app: android_app.id) do
          sync_android_vitals(organization, android_app, vitals)

          GooglePlay::AnomalyNotifier.new(
            organization: organization,
            android_app: android_app
          ).check_and_notify(vitals)
        end
        any_success.make_true
      rescue StandardError => e
        if play_reporting_api_disabled_error?(e)
          api_disabled.make_true
          # Log once per app so admins can still trace the call, but keep
          # the message short — the UI banner carries the actionable fix.
          Rails.logger.warn("AnalyticsSyncJob: Play Developer Reporting API disabled for #{android_app.name} (project_id=#{credential.project_id.inspect}). Enable at #{credential.play_reporting_api_enable_url}")
        else
          Rails.logger.warn("AnalyticsSyncJob: Google vitals failed for #{android_app.name}: #{e.message}")
        end
      end
    end

    if api_disabled.true?
      credential.mark_play_reporting_api_disabled!
    elsif any_success.true?
      credential.mark_play_reporting_api_enabled!
    end
  end

  # Detects the specific 403 that Google returns when the Play Developer
  # Reporting API hasn't been enabled in the service account's project.
  # We match on both the class + status and the SERVICE_DISABLED reason
  # (present in the error body) so we don't misfire on unrelated 403s
  # such as per-app permission denials.
  def play_reporting_api_disabled_error?(error)
    return false unless error.is_a?(Google::Apis::ClientError)
    return false unless error.respond_to?(:status_code) && error.status_code.to_i == 403
    msg = error.message.to_s
    msg.include?("SERVICE_DISABLED") ||
      msg.include?("playdeveloperreporting.googleapis.com") ||
      msg.include?("has not been used in project")
  end

  def sync_android_vitals(organization, android_app, vitals)
    crash_data = vitals.crash_rate(package_name: android_app.package_name, days: 30)
    anr_data = vitals.anr_rate(package_name: android_app.package_name, days: 30)

    anr_by_date = anr_data.each_with_object({}) { |row, h| h[row[:date]] = row }

    snapshots = crash_data.filter_map do |row|
      next unless row[:date]

      anr_row = anr_by_date[row[:date]] || {}
      {
        organization_id: organization.id,
        snapshotable_type: "AndroidApp",
        snapshotable_id: android_app.id,
        snapshot_date: row[:date],
        crash_rate: row[:crash_rate]&.to_f,
        crashes: row[:distinct_users]&.to_i,
        anr_rate: anr_row[:anr_rate]&.to_f,
        data_source: "google_play_vitals",
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    if snapshots.any?
      AppAnalyticsSnapshot.upsert_all(snapshots,
        unique_by: %i[snapshotable_type snapshotable_id snapshot_date])
    end

    Rails.logger.info("AnalyticsSyncJob: Synced #{snapshots.size} Google vitals for #{android_app.name}")
  end
end
