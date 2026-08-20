module AppStoreConnect
  class Sync
    def initialize(organization:)
      @organization = organization
      @credential = @organization.app_store_connect_credentials.active.first!
      @client = Client.new(credential: @credential)
    end

    def call
      change_detector = SyncChangeDetector.new(@organization)
      change_detector.snapshot_before

      # Bulk-resource fan-out: 6 independent Apple API endpoints
      # (bundleIds, certificates, devices, profiles, merchantIds, apps),
      # each with its own upsert/delete-stale cycle. Previously these ran
      # serially inside a single transaction — 5–6 sequential network
      # round-trips while holding a DB connection. Now each runs on its
      # own thread with its own Client (Faraday Net::HTTP isn't safe to
      # share across concurrent requests on one connection). Atomicity
      # across resource types wasn't load-bearing — if a crash between
      # two types leaves partial state, the next sync repairs it.
      bundle_id_remote_ids_ref = Concurrent::AtomicReference.new
      ::Sync::Timings.measure("asc.bulk_resources", org: @organization.id) do
        phases = [
          -> {
            client = AppStoreConnect::Client.new(credential: @credential)
            ids = ::Sync::Timings.measure("asc.bundle_ids", org: @organization.id) { sync_bundle_ids(client) }
            bundle_id_remote_ids_ref.set(ids)
          },
          -> {
            client = AppStoreConnect::Client.new(credential: @credential)
            ::Sync::Timings.measure("asc.certificates", org: @organization.id) { sync_certificates(client) }
          },
          -> {
            client = AppStoreConnect::Client.new(credential: @credential)
            ::Sync::Timings.measure("asc.devices", org: @organization.id) { sync_devices(client) }
          },
          -> {
            client = AppStoreConnect::Client.new(credential: @credential)
            ::Sync::Timings.measure("asc.profiles", org: @organization.id) { sync_profiles(client) }
          },
          -> {
            client = AppStoreConnect::Client.new(credential: @credential)
            ::Sync::Timings.measure("asc.merchant_ids", org: @organization.id) { sync_merchant_ids(client) }
          },
          -> {
            client = AppStoreConnect::Client.new(credential: @credential)
            ::Sync::Timings.measure("asc.apps", org: @organization.id) { sync_apps(client) }
          }
        ]
        ::Sync::ParallelFanout.call(phases) { |phase| phase.call }
      end
      bundle_id_remote_ids = bundle_id_remote_ids_ref.get || []

      # Per-bundle capabilities — M serial calls → parallelized, outside tx.
      ::Sync::Timings.measure("asc.bundle_capabilities", org: @organization.id, count: bundle_id_remote_ids.size) do
        sync_bundle_id_capabilities_for_all(bundle_id_remote_ids)
      end

      # Per-app syncs make multiple API calls (one per app/group) and can be
      # slow. Running them outside the transaction avoids holding a DB
      # connection for the duration of external network calls. Each phase
      # is parallelized per-app — every future builds its own Client
      # because Faraday's Net::HTTP adapter isn't safe to share across
      # threads concurrently.
      ::Sync::Timings.measure("asc.builds_and_versions", org: @organization.id) { sync_builds_and_versions }
      ::Sync::Timings.measure("asc.testflight_groups", org: @organization.id) { sync_testflight_groups }
      ::Sync::Timings.measure("asc.testflight_testers", org: @organization.id) { sync_testflight_testers }

      @credential.mark_sync_success!

      changes = change_detector.detect_changes
      if change_detector.changes?
        SyncCompletedNotificationJob.perform_later(
          organization_id: @organization.id,
          changes_summary: changes
        )
      end

      true
    rescue => e
      @credential.mark_sync_failure!(e.message)
      SyncFailedNotificationJob.perform_later(
        credential_type: "AppStoreConnectCredential",
        credential_id: @credential.id,
        organization_id: @organization.id,
        error_message: e.message
      )
      raise
    end

    private

    # Note: team_id must be set manually by user via UI
    # Apple's API doesn't expose team_id directly in responses
    # Users can find it at: https://developer.apple.com/account/#!/membership/

    def sync_bundle_ids(client = @client)
      rows = []
      remote_ids = []

      AppStoreConnect::BundleIds.new(client).list(limit: 200) do |body|
        (body["data"] || []).each do |item|
          attrs = item["attributes"] || {}
          remote_ids << item["id"]
          rows << {
            organization_id: @organization.id,
            remote_id: item["id"],
            identifier: attrs["identifier"],
            name: attrs["name"],
            platform: attrs["platform"],
            team_id: @credential.team_id,
            raw_json: item
          }
        end
      end

      upsert_all(AppleBundleId, rows, unique_by: %i[organization_id remote_id])

      # Delete bundle IDs that no longer exist in Apple (deleted remotely)
      # Only delete resources for THIS team to avoid affecting other teams
      if remote_ids.any? && @credential.team_id.present?
        deleted_count = @organization.apple_bundle_ids
                                     .where(team_id: @credential.team_id)
                                     .where.not(remote_id: remote_ids)
                                     .delete_all
        Rails.logger.info("Deleted #{deleted_count} bundle IDs for team #{@credential.team_id} that no longer exist in Apple") if deleted_count > 0
      end

      # Capability fan-out is done by the caller OUTSIDE the transaction —
      # see AppStoreConnect::Sync#call. This keeps the transaction brief and
      # lets us parallelize M sequential network calls.
      remote_ids
    end

    def sync_bundle_id_capabilities_for_all(bundle_id_remote_ids)
      return if bundle_id_remote_ids.blank?

      Rails.logger.info("[Sync] Starting parallel capability sync for #{bundle_id_remote_ids.size} bundle IDs")

      ::Sync::ParallelFanout.call(bundle_id_remote_ids) do |bundle_id_remote_id|
        # Each future gets its own ASC Client — Faraday's Net::HTTP adapter
        # is not safe to share across concurrent requests on one instance.
        client = AppStoreConnect::Client.new(credential: @credential)
        service = AppStoreConnect::BundleIds.new(client)
        begin
          sync_capabilities_for_bundle_id(service, bundle_id_remote_id)
        rescue => e
          Rails.logger.error("[Sync] Failed to sync capabilities for bundle ID #{bundle_id_remote_id}: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace.first(5).join("\n")) if e.backtrace
        end
      end
    end

    def sync_capabilities_for_bundle_id(service, bundle_id_remote_id)
      bundle_id = @organization.apple_bundle_ids.find_by(remote_id: bundle_id_remote_id)
      return unless bundle_id

      Rails.logger.info("[Sync] Fetching capabilities for #{bundle_id.identifier} (#{bundle_id_remote_id})")

      rows = []
      capability_remote_ids = []

      service.list_capabilities(bundle_id_remote_id: bundle_id_remote_id) do |body|
        Rails.logger.debug("[Sync] Capability response for #{bundle_id.identifier}: #{(body["data"] || []).size} capabilities")
        (body["data"] || []).each do |item|
          attrs = item["attributes"] || {}
          capability_remote_ids << item["id"]
          rows << {
            apple_bundle_id_id: bundle_id.id,
            remote_id: item["id"],
            capability_type: attrs["capabilityType"],
            settings: attrs["settings"] || {},
            raw_json: item
          }
        end
      end

      Rails.logger.info("[Sync] Found #{rows.size} capabilities for #{bundle_id.identifier}")

      if rows.any?
        AppleBundleIdCapability.upsert_all(
          rows,
          unique_by: %i[apple_bundle_id_id capability_type]
        )
        Rails.logger.info("[Sync] Upserted #{rows.size} capabilities for #{bundle_id.identifier}")

        # Extract app groups and merchant IDs from capability settings
        rows.each do |row|
          extract_identifiers_from_capability(bundle_id, row[:capability_type], row[:settings])
        end
      end

      # Delete capabilities that no longer exist
      if capability_remote_ids.any?
        deleted_count = bundle_id.apple_bundle_id_capabilities
                                 .where.not(remote_id: capability_remote_ids)
                                 .delete_all
        Rails.logger.info("[Sync] Deleted #{deleted_count} stale capabilities for #{bundle_id.identifier}") if deleted_count > 0
      elsif bundle_id.apple_bundle_id_capabilities.any?
        # All capabilities were removed
        deleted_count = bundle_id.apple_bundle_id_capabilities.delete_all
        Rails.logger.info("[Sync] Removed all #{deleted_count} capabilities for #{bundle_id.identifier} (none in Apple)")
      end
    end

    def extract_identifiers_from_capability(bundle_id, capability_type, settings)
      return unless settings.is_a?(Array) && settings.any?

      case capability_type
      when "APP_GROUPS"
        extract_app_groups(bundle_id, settings)
      when "APPLE_PAY"
        extract_merchant_ids_from_settings(bundle_id, settings)
      end
    end

    def extract_app_groups(bundle_id, settings)
      app_group_setting = settings.find { |s| s["key"] == "APP_GROUP_IDENTIFIERS" }
      return unless app_group_setting

      (app_group_setting["options"] || []).each do |option|
        next unless option["enabled"]
        identifier = option["key"]
        next unless identifier&.start_with?("group.")

        # Register App Group if not exists. Under parallel capability sync
        # two bundle IDs may try to create the same app group concurrently;
        # the unique index catches it and we re-read once.
        app_group = begin
          @organization.apple_app_groups.find_or_create_by!(identifier: identifier) do |ag|
            ag.name = identifier
            ag.team_id = @credential.team_id
          end
        rescue ActiveRecord::RecordNotUnique
          @organization.apple_app_groups.find_by!(identifier: identifier)
        end

        # Associate with Bundle ID — same race possible here.
        begin
          AppleBundleIdAppGroup.find_or_create_by!(
            apple_bundle_id: bundle_id,
            apple_app_group: app_group
          )
        rescue ActiveRecord::RecordNotUnique
          # Association already exists; nothing to do.
        end

        Rails.logger.info("[Sync] Associated App Group #{identifier} with #{bundle_id.identifier}")
      rescue => e
        Rails.logger.error("[Sync] Failed to extract app group #{identifier}: #{e.message}")
      end
    end

    def extract_merchant_ids_from_settings(bundle_id, settings)
      merchant_setting = settings.find { |s| s["key"] == "MERCHANT_ID_IDENTIFIERS" }
      return unless merchant_setting

      (merchant_setting["options"] || []).each do |option|
        next unless option["enabled"]
        identifier = option["key"]
        next unless identifier&.start_with?("merchant.")

        # Find the merchant ID in our database (should be synced already)
        merchant_id = @organization.apple_merchant_ids.find_by(identifier: identifier)
        next unless merchant_id

        # Associate with Bundle ID — same parallel-safe pattern as app groups.
        begin
          AppleBundleIdMerchantId.find_or_create_by!(
            apple_bundle_id: bundle_id,
            apple_merchant_id: merchant_id
          )
        rescue ActiveRecord::RecordNotUnique
          # Association already exists; nothing to do.
        end

        Rails.logger.info("[Sync] Associated Merchant ID #{identifier} with #{bundle_id.identifier}")
      rescue => e
        Rails.logger.error("[Sync] Failed to extract merchant ID #{identifier}: #{e.message}")
      end
    end
    def sync_certificates(client = @client)
      rows = []
      remote_ids = []

      # Capture current statuses before upsert for revocation detection
      existing_statuses = @organization.apple_certificates
                                       .pluck(:remote_id, :status)
                                       .to_h

      AppStoreConnect::Certificates.new(client).list(limit: 200) do |body|
        (body["data"] || []).each do |item|
          attrs = item["attributes"] || {}
          remote_ids << item["id"]
          rows << {
            organization_id: @organization.id,
            remote_id: item["id"],
            name: attrs["name"],
            certificate_type: attrs["certificateType"],
            serial_number: attrs["serialNumber"],
            platform: attrs["platform"],
            status: attrs["status"],
            expires_at: parse_time(attrs["expirationDate"]),
            team_id: @credential.team_id,
            raw_json: item
          }
        end
      end

      upsert_all(AppleCertificate, rows, unique_by: %i[organization_id remote_id])

      # Detect newly revoked certificates
      rows.each do |row|
        old_status = existing_statuses[row[:remote_id]]
        new_status = row[:status]
        if old_status.present? && old_status != "Revoked" && new_status == "Revoked"
          cert = @organization.apple_certificates.find_by(remote_id: row[:remote_id])
          if cert
            ResourceRevokedNotificationJob.perform_later(
              resource_type: "AppleCertificate",
              resource_id: cert.id,
              organization_id: @organization.id
            )
          end
        end
      end

      # Delete certificates that no longer exist in Apple (revoked/deleted remotely)
      # Only delete resources for THIS team to avoid affecting other teams
      if remote_ids.any? && @credential.team_id.present?
        deleted_count = @organization.apple_certificates
                                     .where(team_id: @credential.team_id)
                                     .where.not(remote_id: remote_ids)
                                     .delete_all
        Rails.logger.info("Deleted #{deleted_count} certificates for team #{@credential.team_id} that no longer exist in Apple") if deleted_count > 0
      end
    end

    def sync_devices(client = @client)
      rows = []
      remote_ids = []

      AppStoreConnect::Devices.new(client).list(limit: 200) do |body|
        (body["data"] || []).each do |item|
          attrs = item["attributes"] || {}
          remote_ids << item["id"]
          rows << {
            organization_id: @organization.id,
            remote_id: item["id"],
            name: attrs["name"],
            udid: attrs["udid"],
            platform: attrs["platform"],
            device_class: attrs["deviceClass"],
            status: attrs["status"],
            added_at: parse_time(attrs["addedDate"]),
            team_id: @credential.team_id,
            raw_json: item
          }
        end
      end

      upsert_all(AppleDevice, rows, unique_by: %i[organization_id remote_id])

      # Delete devices that no longer exist in Apple (removed remotely)
      # Only delete resources for THIS team to avoid affecting other teams
      if remote_ids.any? && @credential.team_id.present?
        deleted_count = @organization.apple_devices
                                     .where(team_id: @credential.team_id)
                                     .where.not(remote_id: remote_ids)
                                     .delete_all
        Rails.logger.info("Deleted #{deleted_count} devices for team #{@credential.team_id} that no longer exist in Apple") if deleted_count > 0
      end
    end

    def sync_profiles(client = @client)
      rows = []
      remote_ids = []

      # Capture current states before upsert for invalidation detection
      existing_states = @organization.apple_provisioning_profiles
                                     .pluck(:remote_id, :state)
                                     .to_h

      AppStoreConnect::Profiles.new(client).list(limit: 200) do |body|
        # Build a map of bundle ID remote_id -> identifier from included data
        bundle_id_map = {}
        (body["included"] || []).each do |included_item|
          if included_item["type"] == "bundleIds"
            bundle_id_map[included_item["id"]] = included_item.dig("attributes", "identifier")
          end
        end

        (body["data"] || []).each do |item|
          attrs = item["attributes"] || {}
          relationships = item["relationships"] || {}

          # Get the bundle ID remote_id from relationships
          bundle_id_remote_id = relationships.dig("bundleId", "data", "id")

          # Look up the actual identifier from included data
          bundle_id_identifier = bundle_id_map[bundle_id_remote_id]

          remote_ids << item["id"]
          rows << {
            organization_id: @organization.id,
            remote_id: item["id"],
            name: attrs["name"],
            uuid: attrs["uuid"],
            profile_type: attrs["profileType"],
            state: attrs["profileState"],
            platform: attrs["platform"],
            bundle_id_identifier: bundle_id_identifier,
            expires_at: parse_time(attrs["expirationDate"]),
            team_id: @credential.team_id,
            raw_json: item
          }
        end
      end

      upsert_all(AppleProvisioningProfile, rows, unique_by: %i[organization_id remote_id])

      # Detect newly invalidated profiles
      rows.each do |row|
        old_state = existing_states[row[:remote_id]]
        new_state = row[:state]
        if old_state.present? && old_state != "INVALID" && new_state == "INVALID"
          profile = @organization.apple_provisioning_profiles.find_by(remote_id: row[:remote_id])
          if profile
            ResourceRevokedNotificationJob.perform_later(
              resource_type: "AppleProvisioningProfile",
              resource_id: profile.id,
              organization_id: @organization.id
            )
          end
        end
      end

      # Delete profiles that no longer exist in Apple (deleted remotely)
      # Only delete resources for THIS team to avoid affecting other teams
      if remote_ids.any? && @credential.team_id.present?
        deleted_count = @organization.apple_provisioning_profiles
                                     .where(team_id: @credential.team_id)
                                     .where.not(remote_id: remote_ids)
                                     .delete_all
        Rails.logger.info("Deleted #{deleted_count} profiles for team #{@credential.team_id} that no longer exist in Apple") if deleted_count > 0
      end
    end

    def sync_merchant_ids(client = @client)
      rows = []
      remote_ids = []

      AppStoreConnect::MerchantIds.new(client).list(limit: 200) do |body|
        (body["data"] || []).each do |item|
          attrs = item["attributes"] || {}
          remote_ids << item["id"]
          rows << {
            organization_id: @organization.id,
            remote_id: item["id"],
            identifier: attrs["identifier"],
            name: attrs["name"],
            team_id: @credential.team_id,
            raw_json: item
          }
        end
      end

      upsert_all(AppleMerchantId, rows, unique_by: %i[organization_id remote_id])

      # Delete merchant IDs that no longer exist in Apple
      if remote_ids.any? && @credential.team_id.present?
        deleted_count = @organization.apple_merchant_ids
                                     .where(team_id: @credential.team_id)
                                     .where.not(remote_id: remote_ids)
                                     .delete_all
        Rails.logger.info("Deleted #{deleted_count} merchant IDs for team #{@credential.team_id} that no longer exist in Apple") if deleted_count > 0
      end
    rescue => e
      # Merchant IDs API may not be available for all accounts, log and continue
      Rails.logger.warn("[Sync] Failed to sync merchant IDs (may not be available): #{e.message}")
    end

    def sync_apps(client = @client)
      rows = []
      remote_ids = []

      AppStoreConnect::Apps.new(client).list(limit: 200) do |body|
        (body["data"] || []).each do |item|
          attrs = item["attributes"] || {}
          remote_ids << item["id"]
          rows << {
            organization_id: @organization.id,
            app_store_id: item["id"],
            bundle_id: attrs["bundleId"],
            name: attrs["name"],
            sku: attrs["sku"],
            raw_json: item
          }
        end
      end

      upsert_all(AppleApp, rows, unique_by: %i[app_store_id])

      # Delete apps that no longer exist in Apple (removed remotely).
      # Only safe when the org has a single ASC credential — with multiple
      # credentials (different teams), remote_ids only covers the current
      # team's apps and deleting the rest would wipe apps from other teams.
      if remote_ids.any? && @organization.app_store_connect_credentials.active.count == 1
        deleted_count = @organization.apple_apps
                                     .where.not(app_store_id: remote_ids)
                                     .delete_all
        Rails.logger.info("Deleted #{deleted_count} apps that no longer exist in Apple") if deleted_count > 0
      end
    end

    def sync_builds_and_versions
      # Per-app builds + versions (each also fetches per-editable-version
      # validation errors). Every app is fully independent, so fan out in
      # parallel on a bounded pool. Each future builds its own Client
      # because Faraday's Net::HTTP adapter is not thread-safe to share.
      apps = @organization.apple_apps.to_a
      ::Sync::ParallelFanout.call(apps) do |app|
        client = AppStoreConnect::Client.new(credential: @credential)
        sync_builds_for_app(app, client)
        sync_versions_for_app(app, client)
      end
    end

    def sync_builds_for_app(app, client = @client)
      build_rows = []
      build_remote_ids = []

      AppStoreConnect::Builds.new(client).list(app_id: app.app_store_id, limit: 100) do |body|
        # Build map of preReleaseVersion data (contains marketing version like "1.0")
        pre_release_versions = {}
        (body["included"] || []).each do |included_item|
          if included_item["type"] == "preReleaseVersions"
            pre_release_versions[included_item["id"]] = included_item.dig("attributes", "version")
          end
        end

        (body["data"] || []).each do |item|
          attrs = item["attributes"] || {}
          build_remote_ids << item["id"]

          # Get marketing version from preReleaseVersion relationship
          pre_release_id = item.dig("relationships", "preReleaseVersion", "data", "id")
          marketing_version = pre_release_versions[pre_release_id] || "1.0"

          build_rows << {
            organization_id: @organization.id,
            apple_app_id: app.id,
            build_id: item["id"],
            version: marketing_version,  # Marketing version like "1.0"
            build_number: attrs["version"],  # Build number like "1", "2", "14"
            processing_state: attrs["processingState"],
            uploaded_date: parse_time(attrs["uploadedDate"]),
            expires_at: parse_time(attrs["expirationDate"]),
            raw_json: item
          }
        end
      end

      upsert_all(AppleBuild, build_rows, unique_by: %i[build_id])
    rescue => e
      Rails.logger.error("Failed to sync builds for app #{app.name}: #{e.message}")
    end

    def sync_versions_for_app(app, client = @client)
      version_rows = []
      version_remote_ids = []

      # Pre-load existing versions to preserve phased_release_pending
      # FIX: Don't make API calls during sync for phased release status - background job will update this
      existing_versions = @organization.app_store_versions
                                        .where(apple_app_id: app.id)
                                        .index_by(&:version_id)

      versions_service = AppStoreConnect::Versions.new(client)

      versions_service.list(app_id: app.app_store_id, limit: 50) do |body|
        (body["data"] || []).each do |item|
          attrs = item["attributes"] || {}
          version_remote_ids << item["id"]

          # Preserve existing phased_release_pending value, don't make API calls
          existing = existing_versions[item["id"]]

          version_rows << {
            organization_id: @organization.id,
            apple_app_id: app.id,
            version_id: item["id"],
            version_string: attrs["versionString"],
            platform: attrs["platform"],
            app_store_state: attrs["appStoreState"],
            phased_release_pending: existing&.phased_release_pending || false,
            raw_json: item
          }
        end
      end

      upsert_all(AppStoreVersion, version_rows, unique_by: %i[version_id])

      sync_validation_errors_for_versions(app, versions_service)
    rescue StandardError => e
      Rails.logger.error("Failed to sync versions for app #{app.name}: #{e.message}")
    end

    # Fetch pre-submission validation errors for editable versions and persist them.
    # Uses AppStoreVersion.editable scope which already filters to the same set of
    # states the App Store Connect API will accept validation queries against.
    # Each version is fetched independently — a single failure must not abort the
    # rest of the sync.
    def sync_validation_errors_for_versions(app, versions_service)
      app.app_store_versions.editable.find_each do |version|
        begin
          raw_errors = versions_service.validation_errors(version_id: version.version_id) || []
          normalized = raw_errors.map { |err| normalize_validation_error(err) }
          version.update_columns(issues: normalized, issues_synced_at: Time.current)
        rescue StandardError => e
          Rails.logger.warn("AppStoreConnect::Sync: validation_errors failed for version #{version.id}: #{e.class} - #{e.message}")
        end
      end
    end

    # Normalize a validation error into a stable hash shape.
    # AppStoreConnect::Versions#validation_errors currently returns an array of
    # "CODE: detail" strings, but we accept hashes too in case that contract
    # ever changes (we keep the original payload in `raw` regardless).
    def normalize_validation_error(err)
      case err
      when Hash
        code = err["code"] || err[:code] || "UNKNOWN"
        detail = err["detail"] || err[:detail] || err["title"] || err[:title] || "Unknown validation error"
        { "code" => code.to_s, "detail" => detail.to_s, "raw" => err }
      when String
        code, _, detail = err.partition(": ")
        if detail.blank?
          { "code" => "UNKNOWN", "detail" => err, "raw" => err }
        else
          { "code" => code, "detail" => detail, "raw" => err }
        end
      else
        { "code" => "UNKNOWN", "detail" => err.to_s, "raw" => err }
      end
    end

    def sync_testflight_groups
      apps = @organization.apple_apps.to_a
      ::Sync::ParallelFanout.call(apps) do |app|
        client = AppStoreConnect::Client.new(credential: @credential)
        sync_testflight_groups_for_app(app, client)
      end
    end

    def sync_testflight_groups_for_app(app, client = @client)
      rows = []
      remote_ids = []

      AppStoreConnect::Testflight.new(client).list(app_id: app.app_store_id) do |body|
        (body["data"] || []).each do |item|
          attrs = item["attributes"] || {}
          remote_ids << item["id"]

          # Try to get tester count from relationship meta if available, otherwise 0
          # The API doesn't directly provide a count in attributes, and counting included testers
          # would require fetching them. For now we'll default to 0 or check relationship meta.
          tester_count = item.dig("relationships", "betaTesters", "meta", "paging", "total") || 0

          public_link_enabled = attrs["publicLinkEnabled"]
          # Apple's API sometimes returns null for booleans, but our schema requires a value.
          public_link_enabled = false if public_link_enabled.nil?

          is_internal_group = attrs["isInternalGroup"]
          is_internal_group = false if is_internal_group.nil?

          rows << {
            organization_id: @organization.id,
            apple_app_id: app.id,
            remote_id: item["id"],
            name: attrs["name"],
            public_link_enabled: public_link_enabled,
            public_link: attrs["publicLink"],
            is_internal_group: is_internal_group,
            tester_count: tester_count,
            created_at_remote: parse_time(attrs["createdDate"]),
            raw_json: item
          }
        end
      end

      upsert_all(TestflightBetaGroup, rows, unique_by: %i[organization_id remote_id])

      # Delete groups that no longer exist
      if remote_ids.any?
        app.testflight_beta_groups.where.not(remote_id: remote_ids).delete_all
      end
    rescue => e
      Rails.logger.error("Failed to sync beta groups for app #{app.name}: #{e.message}")
    end

    def sync_testflight_testers
      groups = @organization.testflight_beta_groups.to_a
      ::Sync::ParallelFanout.call(groups) do |group|
        client = AppStoreConnect::Client.new(credential: @credential)
        sync_testers_for_group(group, client)
      end
    end

    def sync_testers_for_group(group, client = @client)
      testers = []

      AppStoreConnect::Testflight.new(client).list_testers(group_id: group.remote_id) do |body|
        (body["data"] || []).each do |item|
          attrs = item["attributes"] || {}
          email = attrs["email"]
          next unless email.present?

          testers << {
            email: email,
            first_name: attrs["firstName"],
            last_name: attrs["lastName"],
            invite_status: attrs["state"],
            tester_type: group.is_internal_group? ? "internal" : "external"
          }
        end
      end

      group.update_columns(
        testers: testers,
        tester_count: testers.size,
        updated_at: Time.current
      )
    rescue => e
      Rails.logger.error("Failed to sync testers for group #{group.name}: #{e.message}")
    end

    def upsert_all(model, rows, unique_by:)
      return if rows.empty?
      model.upsert_all(rows, unique_by: unique_by)
    end

    def parse_time(val)
      return nil if val.blank?
      Time.parse(val) rescue nil
    end
  end
end
