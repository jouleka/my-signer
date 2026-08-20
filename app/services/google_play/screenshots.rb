module GooglePlay
  class Screenshots
    # Map resolution to Google Play image type
    IMAGE_TYPES = {
      "1080x1920" => "phoneScreenshots",
      "1200x1920" => "sevenInchScreenshots",
      "1600x2560" => "tenInchScreenshots"
    }.freeze

    def initialize(client)
      @client = client
    end

    def upload_image!(package_name:, language:, image_type:, file_path:)
      upload_images_batch!(
        package_name: package_name,
        language: language,
        image_type: image_type,
        file_paths: [ file_path ],
        delete_existing: false
      )
    end

    # Upload multiple images in a single edit transaction
    def upload_images_batch!(package_name:, language:, image_type:, file_paths:, delete_existing: false, &on_progress)
      edit = @client.create_edit(package_name)
      edit_id = edit.id

      begin
        if delete_existing
          begin
            @client.service.deleteall_edit_image(package_name, edit_id, language, image_type)
          rescue => e
            Rails.logger.warn("GooglePlay::Screenshots - Failed to delete existing images for #{image_type}: #{e.message}")
          end
        end

        file_paths.each do |file_path|
          @client.service.upload_edit_image(
            package_name,
            edit_id,
            language,
            image_type,
            upload_source: file_path,
            content_type: "image/png"
          )
          on_progress&.call(file_path)
        end

        @client.commit_edit(package_name, edit_id)
      rescue => e
        begin
          @client.delete_edit(package_name, edit_id)
        rescue => cleanup_error
          Rails.logger.warn("GooglePlay::Screenshots - Failed to cleanup edit #{edit_id}: #{cleanup_error.message}")
        end
        raise e
      end
    end

    def delete_all_images(package_name:, language:, image_type:)
      edit = @client.create_edit(package_name)
      edit_id = edit.id

      begin
        @client.service.deleteall_edit_image(package_name, edit_id, language, image_type)
        @client.commit_edit(package_name, edit_id)
      rescue => e
        begin
          @client.delete_edit(package_name, edit_id)
        rescue => cleanup_error
          Rails.logger.warn("GooglePlay::Screenshots - Failed to cleanup edit #{edit_id}: #{cleanup_error.message}")
        end
        raise e
      end
    end

    def list_images(package_name:, edit_id:, language:, image_type:)
      response = @client.service.list_edit_images(package_name, edit_id, language, image_type)
      response&.images || []
    end

    # Fetch all current screenshots for a package/language across all image types.
    # Returns a hash of image_type => Array of image metadata hashes.
    # Uses a temporary read-only edit to avoid side effects.
    def fetch_current_screenshots(package_name:, language:)
      edit = @client.create_edit(package_name)
      edit_id = edit.id
      begin
        fetch_current_screenshots_with_edit(package_name: package_name, edit_id: edit_id, language: language)
      ensure
        begin
          @client.delete_edit(package_name, edit_id)
        rescue StandardError => cleanup_error
          Rails.logger.warn("GooglePlay::Screenshots - Failed to cleanup edit #{edit_id}: #{cleanup_error.message}")
        end
      end
    rescue => e
      Rails.logger.warn("GooglePlay::Screenshots - Failed to fetch current screenshots: #{e.message}")
      {}
    end

    # Variant that reuses a caller-provided edit_id, so the store-listing
    # importer can open ONE edit per app and fetch all locales inside it
    # instead of creating/deleting an edit per locale. That collapses 3L
    # edit-create + 3L edit-delete round-trips down to just 1 + 1.
    def fetch_current_screenshots_with_edit(package_name:, edit_id:, language:)
      results = {}
      IMAGE_TYPES.each_value do |image_type|
        begin
          images = list_images(package_name: package_name, edit_id: edit_id, language: language, image_type: image_type)
          results[image_type] = images.map do |img|
            { id: img.id, url: img.url, sha256: img.sha256 }
          end
        rescue => e
          Rails.logger.debug("GooglePlay::Screenshots - No images for #{image_type}: #{e.message}")
          results[image_type] = []
        end
      end
      results
    end

    def image_type_for_resolution(width, height)
      IMAGE_TYPES["#{width}x#{height}"]
    end
  end
end
