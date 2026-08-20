require "time"

module GooglePlay
  class Sync
    class SyncError < StandardError
      attr_reader :failures

      def initialize(failures)
        @failures = failures
        messages = failures.map { |f| f[:message] }.join("\n\n")
        super(messages)
      end
    end

    def initialize(organization:)
      @organization = organization
      @credential = organization.google_play_credentials.active.first
      raise "No active Google Play credential" unless @credential
      @client = GooglePlay::Client.new(credential: @credential)
    end

    # Sync apps (from known package names) and tracks/releases
    def sync_all!(package_names: nil)
      started_at = Time.current
      packages = normalized_package_list(package_names)
      before_app_count = @organization.android_apps.count
      before_build_count = @organization.android_builds.count

      if packages.blank?
        error_msg = "No Android apps found. Google Play API doesn't support automatic app discovery. " \
                   "Please create an Android app record manually with your package name (e.g., com.yourcompany.yourapp) " \
                   "to enable sync. You can find your package name in Google Play Console under your app details."
        raise error_msg
      end

      results = { synced: [], failed: [] }
      results_mutex = Mutex.new

      # Per-app syncs are fully independent: each opens its own edit with
      # Google Play, does 5 reads, and closes the edit. Fan out so apps don't
      # block each other. Each future gets its own Client because the
      # underlying Google API client manages internal state that isn't
      # guaranteed to be thread-safe across concurrent request streams.
      ::Sync::ParallelFanout.call(packages) do |package_name|
        client = GooglePlay::Client.new(credential: @credential)
        ::Sync::Timings.measure("google_play.app", org: @organization.id, package: package_name) do
          sync_one_package(package_name, client, results, results_mutex)
        end
      end

      # If ALL packages failed, raise with helpful message
      if results[:synced].empty? && results[:failed].any?
        raise SyncError.new(results[:failed])
      end

      # If some succeeded but some failed, mark partial success with warnings.
      # Route the per-failure messages through the canonical sanitizer: a
      # failure message can carry the raw text of an upstream exception
      # (e.g. a Google::Apis error echoing credential/OpenSSL material), and
      # this column is surfaced to users.
      if results[:failed].any?
        warning_messages = results[:failed]
          .map { |f| ErrorMessageSanitizer.redact(f[:message].to_s) }
          .join("\n\n---\n\n")
        @credential.update_columns(
          last_synced_at: started_at,
          last_sync_status: "partial",
          last_sync_error: "Synced #{results[:synced].size} app(s), but #{results[:failed].size} failed:\n\n#{warning_messages}"
        )
      else
        @credential.mark_sync_success!(time: started_at)
      end

      # Detect changes for sync completed notifications
      after_app_count = @organization.android_apps.count
      after_build_count = @organization.android_builds.count
      changes = []
      app_diff = after_app_count - before_app_count
      build_diff = after_build_count - before_build_count
      changes << "#{app_diff} new Android apps" if app_diff > 0
      changes << "#{build_diff} new Android builds" if build_diff > 0
      changes << "#{app_diff.abs} Android apps removed" if app_diff < 0
      changes << "#{build_diff.abs} Android builds removed" if build_diff < 0

      if changes.any?
        SyncCompletedNotificationJob.perform_later(
          organization_id: @organization.id,
          changes_summary: changes
        )
      end

      results
    rescue => e
      @credential.mark_sync_failure!(e)
      SyncFailedNotificationJob.perform_later(
        credential_type: "GooglePlayCredential",
        credential_id: @credential.id,
        organization_id: @organization.id,
        error_message: e.message
      )
      raise
    end

    private

    def sync_one_package(package_name, client, results, results_mutex)
      app = @organization.android_apps.where(package_name: package_name).first_or_initialize

      begin
        edit = client.create_edit(package_name)
      rescue Google::Apis::ClientError => e
        if e.message.include?("Package not found") || (e.status_code == 404)
          results_mutex.synchronize do
            results[:failed] << {
              package_name: package_name,
              error: "not_uploaded",
              message: package_not_found_message(package_name)
            }
          end
          app.save! if app.new_record?
          return
        elsif e.message.include?("forbidden") || e.message.include?("403") || (e.status_code == 403)
          results_mutex.synchronize do
            results[:failed] << {
              package_name: package_name,
              error: "no_permission",
              message: permission_denied_message(package_name)
            }
          end
          app.save! if app.new_record?
          return
        else
          raise
        end
      end

      sync_app_metadata(app, edit, client)
      tracks_response = sync_tracks(app, edit, client)
      sync_builds(app, edit, client, tracks_response: tracks_response)

      client.delete_edit(package_name, edit.id)
      results_mutex.synchronize { results[:synced] << package_name }
    end

    def normalized_package_list(package_names)
      if package_names.present?
        Array(package_names)
      else
        # Merge discovered packages with locally registered apps
        discovered = discover_packages_from_google_play
        local = @organization.android_apps.pluck(:package_name)
        (Array(discovered) + Array(local))
      end
        .map { |pkg| pkg.to_s.strip }
        .reject(&:blank?)
        .uniq
    end

    def discover_packages_from_google_play
      developer_id = @credential.developer_account_id.to_s.strip
      service_email = @credential.client_email.to_s.downcase
      return [] if developer_id.blank? || service_email.blank?

      users = @client.list_all_users(developer_id)
      match = users.find { |u| u.email.to_s.downcase == service_email }
      return [] unless match

      # Try to extract package names from grants
      # Note: Google Play API typically doesn't expose package names in grants
      package_names = Array(match.grants)
        .map { |grant| grant.try(:package_name) || grant.try(:app_package_name) }
        .compact
        .uniq

      Rails.logger.info("Discovered #{package_names.length} package(s) from Google Play API") if package_names.any?
      package_names
    rescue => e
      Rails.logger.warn("Unable to discover Google Play packages: #{e.message}")
      []
    end

    def sync_app_metadata(app, edit, client = @client)
      details = client.fetch_app_details(app.package_name, edit.id)
      listings = client.list_app_listings(app.package_name, edit.id)

      serialized_details = serialize_google_object(details)
      serialized_listings = Array(listings&.listings).map { |listing| serialize_google_object(listing) }

      default_language = details&.default_language.presence || serialized_listings.first&.dig("language")
      display_listing = pick_display_listing(serialized_listings, default_language)

      app.name = display_listing&.dig("title").presence || app.name.presence || app.package_name
      # Normalize underscore format (pt_BR) to hyphen format (pt-BR) to match
      # our canonical storage format used in StoreListing.locale.
      if default_language.present?
        normalized_default_language = default_language.to_s.strip.tr("_", "-")
        app.default_language = normalized_default_language if normalized_default_language.present?
      end
      payload = {}
      payload["details"] = serialized_details if serialized_details.present?
      payload["listings"] = serialized_listings if serialized_listings.any?
      app.raw_json = payload

      app.save! if app.changed? || app.new_record?
    end

    def sync_tracks(app, edit, client = @client)
      tracks = client.list_tracks(app.package_name, edit.id)

      Array(tracks.tracks).each do |track|
        rec = app.android_tracks.where(track_name: track.track).first_or_initialize
        rec.status = track.releases&.any? ? "active" : "inactive"
        rec.releases = JSON.parse(track.to_json)
        rec.raw_json = JSON.parse(track.to_json)
        rec.save!
      end

      tracks
    end

    def sync_builds(app, edit, client = @client, tracks_response:)
      release_metadata = build_release_metadata_map(tracks_response)
      rows_by_version = {}

      bundles = client.list_bundles(app.package_name, edit.id)
      Array(bundles&.bundles).each do |bundle|
        row = build_row_from_artifact(app, bundle, release_metadata, artifact_type: "bundle")
        next unless row

        rows_by_version[row[:version_code]] = row
      end

      apks = client.list_apks(app.package_name, edit.id)
      Array(apks&.apks).each do |apk|
        row = build_row_from_artifact(app, apk, release_metadata, artifact_type: "apk")
        next unless row

        rows_by_version[row[:version_code]] ||= row
      end

      upsert_android_builds(rows_by_version.values)
    rescue => e
      Rails.logger.error("Failed to sync builds for #{app.package_name}: #{e.message}")
    end

    def pick_display_listing(listings, default_language)
      return listings.find { |l| l["language"] == default_language } if default_language.present?
      listings.first
    end

    def serialize_google_object(obj)
      return nil unless obj
      JSON.parse(obj.to_json)
    end

    def build_release_metadata_map(tracks_response)
      metadata = {}
      Array(tracks_response&.tracks).each do |track|
        track_name = track.try(:track)
        Array(track.try(:releases)).each do |release|
          version_codes = release.try(:version_codes) || release.try(:versionCodes) || []
          version_codes = Array(version_codes)
          next if version_codes.empty?

          info = {
            name: release.try(:name),
            status: release.try(:status),
            track: track_name
          }

          version_codes.each do |code|
            metadata[code.to_s] = info
          end
        end
      end
      metadata
    rescue => e
      Rails.logger.warn("Failed to build release metadata: #{e.message}")
      {}
    end

    def build_row_from_artifact(app, artifact, release_metadata, artifact_type:)
      data = serialize_google_object(artifact) || {}
      version_code = data["versionCode"] || data["version_code"] || data["versioncode"]
      return nil if version_code.blank?
      version_code = version_code.to_s
      binary = data["binary"] || {}
      release_info = release_metadata[version_code] || {}

      file_size = data["size"] || data["fileSize"] || binary["fileSize"]
      file_size = file_size.to_i if file_size
      min_sdk = data["minSdkVersion"] || data["minimumSdkVersion"]
      min_sdk = min_sdk.to_i if min_sdk
      target_sdk = data["targetSdkVersion"] || data.dig("targeting", "sdkVersion", "value")
      target_sdk = target_sdk.to_i if target_sdk

      {
        organization_id: @organization.id,
        android_app_id: app.id,
        version_code: version_code,
        version_name: release_info[:name] || data["versionName"],
        binary_sha1: binary["sha1"] || data["sha1"],
        binary_sha256: binary["sha256"] || data["sha256"],
        status: release_info[:status] || artifact_type,
        minimum_sdk_version: min_sdk,
        target_sdk_version: target_sdk,
        native_code: Array(data["nativeCode"] || binary["nativeCode"]).compact,
        file_size_bytes: file_size,
        uploaded_at: parse_time(data["createTime"] || data["uploadTime"]),
        raw_json: data.merge("artifact_type" => artifact_type)
      }
    end

    def upsert_android_builds(rows)
      return if rows.blank?
      AndroidBuild.upsert_all(
        rows,
        unique_by: %i[android_app_id version_code]
      )
    end

    def parse_time(value)
      return nil if value.blank?
      Time.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def package_not_found_message(package_name)
      <<~MSG.strip
        App "#{package_name}" not found on Google Play.

        This is NORMAL for new apps. The Google Play API requires the first build
        to be uploaded manually through the Play Console.

        To fix:
        1. Build AAB: mysigner android build
        2. Go to Play Console → Your App → Internal testing → Create release
        3. Upload the AAB file shown in the build output
        4. Save the release (you don't need to roll it out)

        After that first upload, mysigner ship will work automatically.
      MSG
    end

    def permission_denied_message(package_name)
      <<~MSG.strip
        Access denied for "#{package_name}".

        Your service account doesn't have permission to access this app.

        To fix this:
        1. Go to Google Play Console → Users & permissions
        2. Find your service account email
        3. Click "Add app" and select "#{package_name}"
        4. Grant at least "View app information" permission
        5. Try syncing again

        Tip: Permission changes can take a few minutes to propagate.
      MSG
    end
  end
end
