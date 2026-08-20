class AppStoreConnectSyncJob < ApplicationJob
  include AdvisoryLockable
  include SyncRunTrackable

  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(organization_id)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    with_advisory_lock("asc:sync:org:#{organization.id}") do
      track_sync_run(organization: organization, job_name: :asc) do
        AppStoreConnect::Sync.new(organization: organization).call
        sync_store_listings(organization)
      end
    end
  end

  private

  def sync_store_listings(organization)
    return unless organization.app_store_connect_credentials.where(active: true).exists?

    # Every importer is independent per-app and dominated by network I/O
    # (app info, version, localizations, per-locale screenshot sets + per-set
    # screenshots). Fan out so apps don't block each other.
    apps = organization.apple_apps.to_a
    ::Sync::ParallelFanout.call(apps) do |apple_app|
      ::Sync::Timings.measure("asc.store_listing", org: organization.id, app: apple_app.id) do
        StoreListingSync::AppleImporter.new(
          organization: organization,
          apple_app: apple_app
        ).import!
      end
    rescue StandardError => e
      Rails.logger.warn("Store listing sync failed for AppleApp #{apple_app.id}: #{e.message}")
    end
  end
end
