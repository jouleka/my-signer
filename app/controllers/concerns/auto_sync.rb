module AutoSync
  extend ActiveSupport::Concern

  SYNC_STALE_THRESHOLD = 4.hours
  SYNC_MANUAL_MIN_INTERVAL = 5.minutes
  SYNC_ENQUEUE_COOLDOWN = 2.minutes

  private

  def sync_if_stale(organization, threshold: SYNC_STALE_THRESHOLD)
    return unless organization

    enqueue_app_store_connect_sync(organization, min_interval: threshold)
    enqueue_google_play_sync(organization, min_interval: threshold)
  end

  def enqueue_app_store_connect_sync(organization, force: false, min_interval: SYNC_MANUAL_MIN_INTERVAL, cooldown: SYNC_ENQUEUE_COOLDOWN)
    enqueue_sync(organization, platform: :asc, force: force, min_interval: min_interval, cooldown: cooldown)
  end

  def enqueue_google_play_sync(organization, force: false, min_interval: SYNC_MANUAL_MIN_INTERVAL, cooldown: SYNC_ENQUEUE_COOLDOWN)
    enqueue_sync(organization, platform: :gp, force: force, min_interval: min_interval, cooldown: cooldown)
  end

  def sync_lock_present?(org_id)
    sync_lock_present_for_platform?(:asc, org_id)
  end

  def gp_sync_lock_present?(org_id)
    sync_lock_present_for_platform?(:gp, org_id)
  end

  def enqueue_sync(organization, platform:, force:, min_interval:, cooldown:)
    credential = sync_credential_for_platform(organization, platform)
    return :missing_credentials unless credential

    return :running if sync_lock_present_for_platform?(platform, organization.id)

    if !force && min_interval.present? && credential.last_synced_at.present? && credential.last_synced_at > min_interval.ago
      return :fresh
    end

    # Force bypasses "freshness" checks, but never bypasses enqueue burst protection.
    if sync_recently_enqueued?(platform, organization.id)
      return :cooldown
    end

    sync_job_for_platform(platform).perform_later(organization.id)
    mark_sync_enqueued(platform, organization.id, cooldown: cooldown)
    :enqueued
  end

  def sync_credential_for_platform(organization, platform)
    case platform
    when :asc
      organization.app_store_connect_credentials.active.first
    when :gp
      organization.google_play_credentials.active.first
    end
  end

  def sync_job_for_platform(platform)
    platform == :asc ? AppStoreConnectSyncJob : GooglePlaySyncJob
  end

  def sync_lock_present_for_platform?(platform, org_id)
    lock_key = platform == :asc ? "asc:sync:org:#{org_id}" : "gp:sync:org:#{org_id}"
    lock_id = Zlib.crc32(lock_key)
    acquired = ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array([ "SELECT pg_try_advisory_lock(?)", lock_id ])
    )
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array([ "SELECT pg_advisory_unlock(?)", lock_id ])
    ) if acquired
    !acquired
  end

  def sync_enqueue_cache_key(platform, org_id)
    "sync_enqueue:#{platform}:org:#{org_id}"
  end

  def sync_recently_enqueued?(platform, org_id)
    Rails.cache.read(sync_enqueue_cache_key(platform, org_id)).present?
  end

  def mark_sync_enqueued(platform, org_id, cooldown: SYNC_ENQUEUE_COOLDOWN)
    Rails.cache.write(sync_enqueue_cache_key(platform, org_id), true, expires_in: cooldown)
  end
end
