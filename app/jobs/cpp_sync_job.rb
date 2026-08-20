class CppSyncJob < ApplicationJob
  include AdvisoryLockable
  include SyncRunTrackable

  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(organization_id:)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    with_advisory_lock("cpp:sync:org:#{organization.id}") do
      track_sync_run(organization: organization, job_name: :cpp) do
        entitlements = organization.entitlements
        next unless entitlements.custom_product_pages_enabled?

        credential = organization.app_store_connect_credentials.find_by(active: true)
        next unless credential

        client = AppStoreConnect::Client.new(credential: credential)
        service = AppStoreConnect::CustomProductPages.new(client)

        organization.apple_apps.find_each do |apple_app|
          sync_cpps_for_app(organization, apple_app, service)
        rescue StandardError => e
          Rails.logger.warn("CppSyncJob: CPP sync failed for AppleApp #{apple_app.id}: #{e.message}")
        end
      end
    end
  end

  private

  def sync_cpps_for_app(organization, apple_app, service)
    remote_cpp_ids = []
    cpps_to_upsert = []

    service.list(app_id: apple_app.app_store_id) do |page|
      data = page["data"] || []
      data.each do |cpp_data|
        attrs = cpp_data["attributes"] || {}
        remote_id = cpp_data["id"]
        remote_cpp_ids << remote_id

        cpps_to_upsert << {
          organization_id: organization.id,
          apple_app_id: apple_app.id,
          remote_id: remote_id,
          name: attrs["name"].to_s,
          visible: attrs["visible"] != false,
          raw_json: cpp_data,
          created_at: Time.current,
          updated_at: Time.current
        }
      end
    end

    if cpps_to_upsert.any?
      CustomProductPage.upsert_all(cpps_to_upsert, unique_by: :remote_id)
    end

    # Delete stale local CPPs not in API response
    apple_app.custom_product_pages
             .where.not(remote_id: remote_cpp_ids)
             .destroy_all

    # Sync versions and localizations for each CPP
    apple_app.custom_product_pages.find_each do |cpp|
      sync_versions_for_cpp(organization, cpp, service)
    rescue StandardError => e
      Rails.logger.warn("CppSyncJob: Version sync failed for CPP #{cpp.id}: #{e.message}")
    end
  end

  def sync_versions_for_cpp(organization, cpp, service)
    response = service.versions(cpp_id: cpp.remote_id)
    data = response["data"] || []

    remote_version_ids = []
    versions_to_upsert = []

    data.each do |version_data|
      attrs = version_data["attributes"] || {}
      remote_id = version_data["id"]
      remote_version_ids << remote_id

      row = {
        custom_product_page_id: cpp.id,
        organization_id: organization.id,
        remote_id: remote_id,
        state: attrs["state"].to_s.presence || "PREPARE_FOR_SUBMISSION",
        raw_json: version_data,
        created_at: Time.current,
        updated_at: Time.current
      }
      # Only overwrite deep_link if Apple actually returns it (avoid nullifying user-set values)
      row[:deep_link] = attrs["deepLink"] if attrs.key?("deepLink")

      versions_to_upsert << row
    end

    if versions_to_upsert.any?
      CustomProductPageVersion.upsert_all(versions_to_upsert, unique_by: :remote_id)

      # Clear submission_status/submission_error when Apple has moved the
      # version out of PREPARE_FOR_SUBMISSION (confirms the submission succeeded).
      # This avoids showing stale "submitted" banners after the state changes.
      cpp.custom_product_page_versions
         .where.not(state: "PREPARE_FOR_SUBMISSION")
         .where.not(submission_status: nil)
         .update_all(submission_status: nil, submission_error: nil)
    end

    # Delete stale versions
    cpp.custom_product_page_versions
       .where.not(remote_id: remote_version_ids)
       .destroy_all

    # Sync localizations for each version
    cpp.custom_product_page_versions.find_each do |version|
      sync_localizations_for_version(organization, version, service)
    rescue StandardError => e
      Rails.logger.warn("CppSyncJob: Localization sync failed for version #{version.id}: #{e.message}")
    end
  end

  def sync_localizations_for_version(organization, version, service)
    response = service.localizations(version_id: version.remote_id)
    data = response["data"] || []

    remote_loc_ids = []
    locs_to_upsert = []

    data.each do |loc_data|
      attrs = loc_data["attributes"] || {}
      remote_id = loc_data["id"]
      remote_loc_ids << remote_id

      locs_to_upsert << {
        custom_product_page_version_id: version.id,
        organization_id: organization.id,
        remote_id: remote_id,
        locale: attrs["locale"].to_s,
        promotional_text: attrs["promotionalText"],
        raw_json: loc_data,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    if locs_to_upsert.any?
      CustomProductPageLocalization.upsert_all(locs_to_upsert, unique_by: :remote_id)
    end

    # Delete stale localizations
    version.custom_product_page_localizations
           .where.not(remote_id: remote_loc_ids)
           .destroy_all
  end
end
