module Api
  module V1
    class ScreenshotExportsController < ApplicationController
      MAX_FILE_SIZE = 15.megabytes
      MAX_ENCODED_IMAGE_DATA_SIZE = (MAX_FILE_SIZE * 4.0 / 3).ceil
      MAX_DIMENSION = 4096

      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :set_project
      before_action :verify_read_scope, only: [ :index, :download ]
      before_action :verify_write_scope, only: [ :create, :destroy ]
      before_action :require_paid_export_plan!, only: [ :index, :create, :download ]
      before_action :ensure_project_plan_access!, only: [ :create ]

      # GET /api/v1/organizations/:organization_id/screenshot_projects/:screenshot_project_id/screenshot_exports
      def index
        authorize @organization, :show?

        # Prefer cloud exports if available, fall back to local filesystem scan
        cloud_exports = @project.screenshot_exports.includes(image_attachment: :blob)
        if cloud_exports.any?
          exports = cloud_exports.filter_map do |export|
            next unless export.image.attached?

            {
              resolution: export.resolution,
              scene_position: export.scene_position,
              file_size: export.image.blob.byte_size,
              file_name: export.image.blob.filename.to_s,
              locale: export.locale,
              export_format: export.export_format,
              storage: "cloud"
            }
          end
        else
          exports = scan_exports
        end

        render json: { data: { exports: exports } }
      end

      def create
        authorize @organization, :manage_resources?

        width = params[:width].to_i
        height = params[:height].to_i
        position = params[:scene_position].to_i
        image_data = params[:image_data]
        locale = params[:locale].presence
        export_format = params[:export_format].presence || "standard"
        scene_positions = @project.screenshot_scenes.pluck(:position)

        if width <= 0 || width > MAX_DIMENSION || height <= 0 || height > MAX_DIMENSION
          return render_invalid_request("Width and height must be between 1 and #{MAX_DIMENSION}")
        end

        unless scene_positions.include?(position)
          return render_invalid_request("Scene position must match an existing project scene")
        end

        if image_data.blank?
          return render_invalid_request("Image data is required")
        end

        encoded = image_data.to_s.sub(%r{^data:image/png;base64,}, "")
        if encoded.bytesize > MAX_ENCODED_IMAGE_DATA_SIZE
          return render_invalid_request("Encoded image data too large")
        end

        # Decode base64 (Base64.decode64 never raises - validate result instead)
        raw = Base64.decode64(encoded)

        # Validate PNG magic bytes
        unless raw.byteslice(0, 4) == "\x89PNG".b
          return render_invalid_request("Invalid image data: not a valid PNG file")
        end

        # Validate file size
        if raw.bytesize > MAX_FILE_SIZE
          return render_invalid_request("Image too large (max #{MAX_FILE_SIZE / 1.megabyte}MB)")
        end

        file_name = "screenshot_#{position.to_s.rjust(2, '0')}.png"
        resolution = "#{width}x#{height}"
        quota_error = nil

        @organization.with_lock do
          @project.lock!

          # Check quota: account for overwrite of existing cloud export
          existing_export = @project.screenshot_exports.find_by(
            resolution: resolution,
            scene_position: position,
            locale: locale
          )
          existing_size = existing_export&.image&.attached? ? existing_export.image.blob.byte_size : 0
          required_delta = [ raw.bytesize - existing_size, 0 ].max
          unless @project.org_within_export_quota?(required_delta, use_cache: false)
            limit_label = ActiveSupport::NumberHelper.number_to_human_size(@project.max_export_storage_bytes_per_organization)
            quota_error = "Organization export storage quota exceeded (max #{limit_label})"
            next
          end

          # Store via ActiveStorage (cloud-compatible)
          ScreenshotExport.upsert_export!(
            project: @project,
            resolution: resolution,
            scene_position: position,
            locale: locale,
            image_data: raw,
            export_format: export_format
          )

          # Also write to local filesystem for backward compatibility
          resolution_dir = @project.ensure_resolution_directory!(width: width, height: height)
          File.binwrite(resolution_dir.join(file_name), raw)
        end

        if quota_error
          return render_quota_exhausted(
            quota_error,
            current_plan: @organization.plan_tier,
            next_plan: @organization.entitlements.next_plan_tier,
            suggestion: quota_upgrade_suggestion(
              current_plan: @organization.plan_tier,
              next_plan: @organization.entitlements.next_plan_tier,
              feature: "export storage"
            )
          )
        end

        ScreenshotProject.invalidate_export_quota_cache!(@organization.id)

        render json: {
          data: {
            resolution: resolution,
            scene_position: position,
            file_size: raw.bytesize,
            file_name: file_name,
            storage: "cloud"
          }
        }, status: :created
      end

      # GET /api/v1/organizations/:organization_id/screenshot_projects/:screenshot_project_id/screenshot_exports/download
      def download
        authorize @organization, :show?

        preset_filter = params[:preset]
        fastlane_layout = ActiveModel::Type::Boolean.new.cast(params[:fastlane])

        # Prefer cloud exports (ActiveStorage) if available, fall back to local filesystem
        cloud_exports = @project.screenshot_exports.includes(image_attachment: :blob)
        cloud_exports = cloud_exports.where.not(image_attachment: nil) if cloud_exports.respond_to?(:where)

        if cloud_exports.any? { |e| e.image.attached? }
          temp_zip = generate_cloud_zip(cloud_exports, preset_filter: preset_filter, fastlane: fastlane_layout)
        else
          exports_dir = @project.exports_directory
          unless exports_dir.exist?
            return render_not_found("No exports found")
          end

          temp_zip = if fastlane_layout
            generate_fastlane_zip_file(exports_dir)
          else
            generate_zip_file(exports_dir, preset_filter)
          end
        end

        filename = fastlane_layout ? "#{@project.name.parameterize}_fastlane_screenshots.zip" : "#{@project.name.parameterize}_screenshots.zip"

        send_file temp_zip.path,
                  type: "application/zip",
                  disposition: "attachment",
                  filename: filename
      ensure
        temp_zip&.close
        temp_zip&.unlink
      end

      # DELETE /api/v1/organizations/:organization_id/screenshot_projects/:screenshot_project_id/screenshot_exports
      def destroy
        authorize @organization, :manage_resources?

        # Remove cloud exports (ActiveStorage)
        @project.screenshot_exports.destroy_all

        # Remove local filesystem exports (backward compatibility)
        @project.clear_exports_directory!

        ScreenshotProject.invalidate_export_quota_cache!(@organization.id)

        render json: { data: { message: "Exports deleted" } }
      end

      private

      def require_paid_export_plan!
        return if @organization.store_upload_enabled?

        required_plan = Pricing::Entitlements.required_plan_for(:store_uploads)
        render_plan_upgrade_required(
          required_plan: required_plan,
          current_plan: @organization.plan_tier,
          message: "Server-side screenshot exports are available on paid plans only",
          suggestion: plan_upgrade_suggestion(
            current_plan: @organization.plan_tier,
            required_plan: required_plan,
            feature: "store uploads"
          )
        )
      end

      def ensure_project_plan_access!
        return if @project.plan_accessible_on_current_plan?

        render json: {
          error: "plan_frozen",
          message: @project.plan_frozen_reason || "This screenshot project is frozen on the current plan.",
          current_plan: @organization.plan_tier.to_s,
          project_id: @project.id,
          project_name: @project.name,
          plan_access_state: @project.plan_access_state,
          frozen_project_ids: ScreenshotProject.plan_frozen_ids_for(@organization),
          accessible_project_ids: ScreenshotProject.plan_accessible_ids_for(@organization),
          suggestion: "Keep the oldest screenshot projects on the current plan or upgrade to unlock this project.",
          timestamp: Time.current.iso8601
        }, status: :forbidden
      end

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_project
        @project = @organization.screenshot_projects.find(params[:screenshot_project_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Screenshot project")
      end

      def verify_read_scope
        verify_read_scope!
      end

      def verify_write_scope
        verify_write_scope!
      end

      def scan_exports
        dir = @project.exports_directory
        return [] unless dir.exist?

        results = []
        dir.children.select(&:directory?).each do |resolution_dir|
          resolution = resolution_dir.basename.to_s
          resolution_dir.children.select { |f| f.extname == ".png" }.sort.each do |file|
            position = file.basename(".png").to_s.match(/screenshot_(\d+)/)&.captures&.first&.to_i
            results << {
              resolution: resolution,
              scene_position: position,
              file_size: file.size,
              file_name: file.basename.to_s
            }
          end
        end
        results
      end

      def generate_cloud_zip(exports, preset_filter: nil, fastlane: false)
        require "zip"

        temp_file = Tempfile.new([ "cloud_export", ".zip" ])
        temp_file.binmode

        filtered_exports = exports.select { |e| e.image.attached? }

        if preset_filter.present?
          filtered_exports = filtered_exports.select do |e|
            resolution_matches_preset?(e.resolution, preset_filter)
          end
        end

        locales = @project.multi_locale? ? @project.locales : [ "en-US" ]

        Zip::OutputStream.open(temp_file.path) do |zip|
          filtered_exports.each do |export|
            file_name = export.image.blob.filename.to_s

            if fastlane
              locale = export.locale.presence || "en-US"
              zip_path = "screenshots/#{locale}/#{file_name}"
            elsif export.locale.present?
              zip_path = "#{export.locale}/#{export.resolution}/#{file_name}"
            else
              zip_path = "#{export.resolution}/#{file_name}"
            end

            zip.put_next_entry(zip_path)
            export.image.blob.open do |tempfile|
              while (chunk = tempfile.read(1.megabyte))
                zip.write(chunk)
              end
            end
          end
        end

        temp_file
      end

      def generate_fastlane_zip_file(exports_dir)
        require "zip"

        temp_file = Tempfile.new([ "fastlane_export", ".zip" ])
        temp_file.binmode

        locales = @project.multi_locale? ? @project.locales : [ "en-US" ]

        Zip::OutputStream.open(temp_file.path) do |zip|
          exports_dir.glob("**/*.png").each do |file|
            file_name = file.basename.to_s

            locales.each do |locale|
              fastlane_path = "screenshots/#{locale}/#{file_name}"
              zip.put_next_entry(fastlane_path)
              File.open(file, "rb") do |f|
                while (chunk = f.read(1.megabyte))
                  zip.write(chunk)
                end
              end
            end
          end
        end

        temp_file
      end

      def generate_zip_file(exports_dir, preset_filter)
        require "zip"

        temp_file = Tempfile.new([ "screenshot_export", ".zip" ])
        temp_file.binmode

        Zip::OutputStream.open(temp_file.path) do |zip|
          exports_dir.glob("**/*.png").each do |file|
            relative_path = file.relative_path_from(exports_dir).to_s

            if preset_filter.present?
              resolution = file.parent.basename.to_s
              next unless resolution_matches_preset?(resolution, preset_filter)
            end

            zip.put_next_entry(relative_path)
            File.open(file, "rb") do |f|
              while (chunk = f.read(1.megabyte))
                zip.write(chunk)
              end
            end
          end
        end

        temp_file
      end

      def resolution_matches_preset?(resolution, preset)
        presets = ScreenshotProject::EXPORT_PRESETS[preset]
        return false unless presets

        presets.any? { |p| "#{p[:width]}x#{p[:height]}" == resolution }
      end
    end
  end
end
