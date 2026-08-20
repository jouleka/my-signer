class ScreenshotUploadJob < ApplicationJob
  queue_as :screenshot_uploads

  # Retry only transient network/connection errors
  retry_on Faraday::ConnectionFailed, wait: :polynomially_longer, attempts: 3
  retry_on Faraday::TimeoutError, wait: :polynomially_longer, attempts: 3
  retry_on Google::Apis::TransmissionError, wait: :polynomially_longer, attempts: 3

  def perform(screenshot_upload_id)
    upload = claim_upload(screenshot_upload_id)
    return unless upload

    case upload.target
    when "app_store_connect"
      upload_to_app_store_connect(upload)
    when "google_play"
      upload_to_google_play(upload)
    when "custom_product_page"
      upload_to_custom_product_page(upload)
    else
      upload.mark_failed!("Unknown target: #{upload.target}")
    end
  rescue ActiveRecord::RecordNotFound
    # Upload was deleted, nothing to do
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError, Google::Apis::TransmissionError => e
    # Let retry_on handle these - re-raise so the retry mechanism works
    Rails.logger.warn("ScreenshotUploadJob transient error (will retry): #{e.class} - #{e.message}")
    # Reset to pending so retry can claim it again
    upload&.update_columns(status: "pending", started_at: nil)
    raise
  rescue => e
    Rails.logger.error("ScreenshotUploadJob failed: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
    upload&.mark_failed!(e.message)
  ensure
    cleanup_temp_files!
  end

  private

  # Tempfiles created by resolve_cloud_export_files must outlive that method
  # (the resolved Pathnames are uploaded later in perform), so we stash the
  # Tempfile objects here and unlink them once perform finishes.
  def cloud_export_tempfiles
    @cloud_export_tempfiles ||= []
  end

  def cleanup_temp_files!
    cloud_export_tempfiles.each do |tempfile|
      tempfile.close! # close + unlink; safe if already closed
    rescue => e
      Rails.logger.warn("ScreenshotUploadJob: failed to unlink temp file: #{e.class} - #{e.message}")
    end
    cloud_export_tempfiles.clear
  end

  def claim_upload(screenshot_upload_id)
    ScreenshotUpload.transaction do
      upload = ScreenshotUpload.lock.find_by(id: screenshot_upload_id)
      return nil unless upload&.pending?
      upload.mark_in_progress!
      upload
    end
  end

  def upload_to_app_store_connect(upload)
    config = upload.config
    organization = upload.organization
    project = upload.screenshot_project

    credential = organization.app_store_connect_credentials.find_by(active: true)
    unless credential
      upload.mark_failed!("No active App Store Connect credential found")
      return
    end

    client = AppStoreConnect::Client.new(credential: credential)
    versions_service = AppStoreConnect::Versions.new(client)
    screenshots_service = AppStoreConnect::Screenshots.new(client)

    version_id = config["version_id"]
    replace_existing = config["replace_existing"] == true

    # Determine locales to upload: batch-locale or single
    locales = config["locales"].presence || [ config["locale"] || "en-US" ]

    # Fetch all localizations once (shared across locales)
    localizations = versions_service.localizations(version_id: version_id)

    # Resolve uploadable files (shared across locales — same export files, different store localizations)
    uploadable = resolve_asc_uploadable_files(project: project, config: config)
    if uploadable.nil?
      upload.mark_failed!("No export files match App Store Connect display types")
      return
    end

    files_per_locale = uploadable.values.flatten.count
    total_files = files_per_locale * locales.size
    completed = 0
    failures = []
    upload.update_progress!(completed: 0, total: total_files)

    locales.each do |locale|
      localization = localizations.find { |loc| loc.dig("attributes", "locale") == locale }

      unless localization
        failures << "[#{locale}] Localization not found for version #{version_id}"
        completed += files_per_locale
        upload.update_progress!(completed: completed, total: total_files, current_locale: locale)
        next
      end

      localization_id = localization["id"]

      # List sets ONCE per locale (not per display type)
      existing_sets = screenshots_service.list_screenshot_sets(localization_id: localization_id)

      uploadable.each do |display_type, files|
        set = existing_sets.find { |s| s.dig("attributes", "screenshotDisplayType") == display_type }

        if set && replace_existing
          # Delete entire set in 1 call (instead of listing + N individual deletes)
          screenshots_service.delete_screenshot_set(id: set["id"])
          set = nil
        end

        unless set
          response = screenshots_service.create_screenshot_set(localization_id: localization_id, display_type: display_type)
          set = response["data"]
        end

        set_id = set["id"]

        files.each do |file|
          begin
            screenshots_service.upload_screenshot!(set_id: set_id, file_path: file.to_s)
          rescue => e
            failures << "[#{locale}] #{file.basename}: #{e.message}"
            Rails.logger.error("Screenshot upload failed for #{file} (#{locale}): #{e.message}")
          end
          completed += 1
          upload.update_progress!(completed: completed, total: total_files, current_file: file.basename.to_s, current_locale: locale)
        end
      end
    end

    if failures.any?
      upload.mark_failed!("#{failures.size} file(s) failed: #{failures.first(3).join('; ')}")
    else
      upload.mark_completed!
    end
  end

  # Resolves and deduplicates export files for App Store Connect upload.
  # Returns a Hash of { display_type => [file_paths] } or nil if none match.
  # Falls back to ActiveStorage cloud exports when local files don't exist.
  def resolve_asc_uploadable_files(project:, config:)
    exports_dir = project.exports_directory
    files_by_resolution = {}

    if exports_dir.exist?
      exports_dir.children.select(&:directory?).each do |resolution_dir|
        resolution = resolution_dir.basename.to_s
        pngs = resolution_dir.children.select { |f| f.extname == ".png" }.sort
        files_by_resolution[resolution] = pngs if pngs.any?
      end
    end

    # Fall back to cloud exports if no local files found
    if files_by_resolution.empty?
      files_by_resolution = resolve_cloud_export_files(project)
    end

    return nil if files_by_resolution.empty?

    uploadable = files_by_resolution.select do |resolution, _files|
      AppStoreConnect::Screenshots::DISPLAY_TYPES.key?(resolution)
    end

    return nil if uploadable.empty?

    if config["presets"].present?
      preset_resolutions = config["presets"].flat_map do |preset_key|
        (ScreenshotProject::EXPORT_PRESETS[preset_key] || []).map { |p| "#{p[:width]}x#{p[:height]}" }
      end
      uploadable = uploadable.select { |resolution, _| preset_resolutions.include?(resolution) }
    end

    # Deduplicate by display type — multiple resolutions can map to the same type
    # (e.g. 1320x2868 and 1290x2796 both -> APP_IPHONE_67). Keep highest resolution only.
    by_display_type = {}
    uploadable.each do |resolution, files|
      display_type = AppStoreConnect::Screenshots::DISPLAY_TYPES[resolution]
      w, h = resolution.split("x").map(&:to_i)
      pixels = w * h
      if !by_display_type[display_type] || pixels > by_display_type[display_type][:pixels]
        by_display_type[display_type] = { resolution: resolution, files: files, pixels: pixels }
      end
    end

    by_display_type.transform_values { |v| v[:files] }
      .each_with_object({}) { |(display_type, files), h| h[display_type] = files }
  end

  def upload_to_google_play(upload)
    config = upload.config
    organization = upload.organization
    project = upload.screenshot_project

    credential = organization.google_play_credentials.find_by(active: true)
    unless credential
      upload.mark_failed!("No active Google Play credential found")
      return
    end

    client = GooglePlay::Client.new(credential: credential)
    screenshots_service = GooglePlay::Screenshots.new(client)

    package_name = config["package_name"]
    replace_existing = config["replace_existing"] == true

    # Determine languages to upload: batch-locale or single
    languages = config["locales"].presence || [ config["language"] || "en-US" ]

    unless package_name.present?
      upload.mark_failed!("Package name is required")
      return
    end

    # Resolve uploadable files (shared across languages)
    uploadable = resolve_gp_uploadable_files(project: project, config: config)
    if uploadable.nil?
      upload.mark_failed!("No export files match Google Play image types")
      return
    end

    files_per_language = uploadable.values.flatten.count
    total_files = files_per_language * languages.size
    completed = 0
    failures = []
    upload.update_progress!(completed: 0, total: total_files)

    languages.each do |language|
      # Create ONE edit per language and upload all image types within it
      begin
        edit = client.create_edit(package_name)
        edit_id = edit.id

        uploadable.each do |resolution, files|
          image_type = GooglePlay::Screenshots::IMAGE_TYPES[resolution]

          begin
            if replace_existing
              begin
                client.service.deleteall_edit_image(package_name, edit_id, language, image_type)
              rescue => e
                Rails.logger.warn("GooglePlay - Failed to delete existing images for #{image_type} (#{language}): #{e.message}")
              end
            end

            files.each do |file|
              client.service.upload_edit_image(
                package_name,
                edit_id,
                language,
                image_type,
                upload_source: file.to_s,
                content_type: "image/png"
              )
              completed += 1
              upload.update_progress!(completed: completed, total: total_files, current_file: file.basename.to_s, current_locale: language)
            end
          rescue => e
            failures << "[#{language}] #{image_type}: #{e.message}"
            Rails.logger.error("Google Play upload failed for #{image_type} (#{language}): #{e.message}")
            completed += files.size
            upload.update_progress!(completed: completed, total: total_files, current_locale: language)
          end
        end

        client.commit_edit(package_name, edit_id)
      rescue => e
        failures << "[#{language}] edit failed: #{e.message}"
        Rails.logger.error("Google Play edit failed for #{language}: #{e.message}")
        # Attempt to clean up the edit
        begin
          client.delete_edit(package_name, edit_id) if edit_id
        rescue => cleanup_error
          Rails.logger.warn("GooglePlay - Failed to cleanup edit #{edit_id}: #{cleanup_error.message}")
        end
        # Count remaining files for this language as completed (for progress tracking)
        remaining = uploadable.values.flatten.count - (completed % files_per_language)
        completed += remaining if remaining > 0
        upload.update_progress!(completed: completed, total: total_files, current_locale: language)
      end
    end

    if failures.any?
      upload.mark_failed!("#{failures.size} type(s) failed: #{failures.first(3).join('; ')}")
    else
      upload.mark_completed!
    end
  end

  def upload_to_custom_product_page(upload)
    config = upload.config
    organization = upload.organization
    project = upload.screenshot_project

    credential = organization.app_store_connect_credentials.find_by(active: true)
    unless credential
      upload.mark_failed!("No active App Store Connect credential found")
      return
    end

    client = AppStoreConnect::Client.new(credential: credential)
    screenshots_service = AppStoreConnect::Screenshots.new(client)

    cpp_localization_id = config["cpp_localization_id"]
    replace_existing = config["replace_existing"] == true

    unless cpp_localization_id.present?
      upload.mark_failed!("CPP localization ID is required")
      return
    end

    # Resolve uploadable files (reuse existing ASC method)
    uploadable = resolve_asc_uploadable_files(project: project, config: config)
    if uploadable.nil?
      upload.mark_failed!("No export files match App Store Connect display types")
      return
    end

    total_files = uploadable.values.flatten.count
    completed = 0
    failures = []
    upload.update_progress!(completed: 0, total: total_files)

    # List existing sets ONCE (not per display type)
    existing_sets = screenshots_service.list_cpp_screenshot_sets(localization_id: cpp_localization_id)

    uploadable.each do |display_type, files|
      set = existing_sets.find { |s| s.dig("attributes", "screenshotDisplayType") == display_type }

      if set && replace_existing
        # Delete entire set in 1 API call (instead of listing + N individual deletes)
        screenshots_service.delete_screenshot_set(id: set["id"])
        set = nil
      end

      unless set
        response = screenshots_service.create_screenshot_set(
          localization_id: cpp_localization_id,
          display_type: display_type,
          localization_type: :custom_product_page
        )
        set = response["data"]
      end

      set_id = set["id"]

      files.each do |file|
        begin
          screenshots_service.upload_screenshot!(set_id: set_id, file_path: file.to_s)
        rescue => e
          failures << "#{file.basename}: #{e.message}"
          Rails.logger.error("CPP screenshot upload failed for #{file}: #{e.message}")
        end
        completed += 1
        upload.update_progress!(completed: completed, total: total_files, current_file: file.basename.to_s)
      end
    end

    if failures.any?
      upload.mark_failed!("#{failures.size} file(s) failed: #{failures.first(3).join('; ')}")
    else
      upload.mark_completed!
    end
  end

  # Resolves export files for Google Play upload.
  # Returns a Hash of { resolution => [file_paths] } or nil if none match.
  # Falls back to ActiveStorage cloud exports when local files don't exist.
  def resolve_gp_uploadable_files(project:, config:)
    exports_dir = project.exports_directory
    files_by_resolution = {}

    if exports_dir.exist?
      exports_dir.children.select(&:directory?).each do |resolution_dir|
        resolution = resolution_dir.basename.to_s
        pngs = resolution_dir.children.select { |f| f.extname == ".png" }.sort
        files_by_resolution[resolution] = pngs if pngs.any?
      end
    end

    # Fall back to cloud exports if no local files found
    if files_by_resolution.empty?
      files_by_resolution = resolve_cloud_export_files(project)
    end

    return nil if files_by_resolution.empty?

    uploadable = files_by_resolution.select do |resolution, _files|
      GooglePlay::Screenshots::IMAGE_TYPES.key?(resolution)
    end

    return nil if uploadable.empty?

    if config["presets"].present?
      preset_resolutions = config["presets"].flat_map do |preset_key|
        (ScreenshotProject::EXPORT_PRESETS[preset_key] || []).map { |p| "#{p[:width]}x#{p[:height]}" }
      end
      uploadable = uploadable.select { |resolution, _| preset_resolutions.include?(resolution) }
    end

    uploadable
  end

  # Downloads cloud exports (ActiveStorage) to local temp files, grouped by resolution.
  # Returns a Hash of { resolution => [Pathname] } mirroring the local filesystem structure.
  def resolve_cloud_export_files(project)
    cloud_exports = project.screenshot_exports.includes(image_attachment: :blob)
    return {} unless cloud_exports.any? { |e| e.image.attached? }

    files_by_resolution = {}
    cloud_exports.select { |e| e.image.attached? }.each do |export|
      resolution = export.resolution
      files_by_resolution[resolution] ||= []

      # Download blob to a temp file for upload. Track the Tempfile so perform's
      # ensure block can unlink it after the upload finishes (otherwise these
      # leak — the cloud-export download path never cleaned them up).
      temp_file = Tempfile.new([ "cloud_export_#{export.scene_position}", ".png" ])
      cloud_export_tempfiles << temp_file
      temp_file.binmode
      export.image.blob.open do |blob_file|
        IO.copy_stream(blob_file, temp_file)
      end
      temp_file.close

      files_by_resolution[resolution] << Pathname.new(temp_file.path)
    end

    # Sort files within each resolution for consistency
    files_by_resolution.transform_values(&:sort)
  end
end
