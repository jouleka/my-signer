class GooglePlaySyncJob < ApplicationJob
  include AdvisoryLockable
  include SyncRunTrackable

  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(organization_id, package_names = nil)
    org = Organization.find_by(id: organization_id)
    return unless org

    with_advisory_lock("gp:sync:org:#{org.id}") do
      track_sync_run(organization: org, job_name: :google_play) do
        GooglePlay::Sync.new(organization: org).sync_all!(package_names: package_names)
        sync_store_listings(org)
      end
    end
  end

  private

  def sync_store_listings(organization)
    credential = organization.google_play_credentials.find_by(active: true)
    return unless credential

    # Fan out per-app. Each future builds its own Google Play Client; the
    # underlying Google::Apis service isn't documented as safe for
    # concurrent requests on a single instance, so we isolate per-thread.
    # That still saves the O(N) re-auth we had before, because each thread
    # only builds one client regardless of how many apps it processes.
    apps = organization.android_apps.to_a
    ::Sync::ParallelFanout.call(apps) do |android_app|
      client = GooglePlay::Client.new(credential: credential)
      ::Sync::Timings.measure("google_play.store_listing", org: organization.id, app: android_app.id) do
        StoreListingSync::GoogleImporter.new(
          organization: organization,
          android_app: android_app,
          client: client
        ).import!
      end
    rescue StandardError => e
      Rails.logger.warn("Store listing sync failed for AndroidApp #{android_app.id}: #{e.message}")
    end
  end
end
