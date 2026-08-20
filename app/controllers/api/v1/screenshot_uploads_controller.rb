module Api
  module V1
    class ScreenshotUploadsController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :verify_read_scope, only: [ :index, :show ]
      before_action :verify_write_scope, only: [ :create ]
      before_action :ensure_project_plan_access!, only: [ :create ]

      # GET /api/v1/organizations/:organization_id/screenshot_uploads
      def index
        authorize @organization, :show?

        uploads = @organization.screenshot_uploads.recent

        render json: {
          data: {
            uploads: uploads.map { |u| upload_json(u) }
          }
        }
      end

      # GET /api/v1/organizations/:organization_id/screenshot_uploads/:id
      def show
        authorize @organization, :show?

        upload = @organization.screenshot_uploads.find(params[:id])

        render json: { data: upload_json(upload) }
      rescue ActiveRecord::RecordNotFound
        render_not_found("Screenshot upload")
      end

      # POST /api/v1/organizations/:organization_id/screenshot_uploads
      def create
        authorize @organization, :manage_resources?

        unless @organization.store_upload_enabled?
          required_plan = Pricing::Entitlements.required_plan_for(:store_uploads)
          return render_plan_upgrade_required(
            required_plan: required_plan,
            current_plan: @organization.plan_tier,
            message: "Store uploads are available on paid plans only",
            suggestion: plan_upgrade_suggestion(current_plan: @organization.plan_tier, required_plan: required_plan, feature: "store uploads")
          )
        end

        # Rate limit: 1 upload per 30 seconds per token
        rate_key = "api_screenshot_upload:#{current_api_token&.id || current_user.id}"
        if Rails.cache.read(rate_key)
          return render json: { error: "Please wait before starting another upload" }, status: :too_many_requests
        end

        project = @organization.screenshot_projects.find_by(id: params[:project_id])
        unless project
          return render_not_found("Screenshot project")
        end

        target = params[:target]
        unless ScreenshotUpload::TARGETS.include?(target)
          return render_invalid_request("Target must be one of: #{ScreenshotUpload::TARGETS.join(', ')}")
        end

        Rails.cache.write(rate_key, true, expires_in: 30.seconds)

        config = params[:config]&.permit(:version_id, :locale, :package_name, :language, :replace_existing, :all_locales, presets: [], locales: [])&.to_h || {}
        config, config_error = normalize_store_upload_config(project: project, target: target, config: config)
        return render_invalid_request(config_error) if config_error

        upload = nil
        conflict_error = nil
        daily_limit_error = nil
        daily_limit_suggestion = nil
        exports_error = nil

        @organization.with_lock do
          project.lock!

          daily_limit = ScreenshotUpload.daily_limit_for(@organization)
          unless ScreenshotUpload.within_daily_limit?(@organization.id, limit: daily_limit)
            daily_limit_error = "Daily upload limit reached (max #{daily_limit} uploads per 24 hours)"
            daily_limit_suggestion = quota_upgrade_suggestion(
              current_plan: @organization.plan_tier,
              next_plan: @organization.entitlements.next_plan_tier,
              feature: "daily store uploads"
            )
            next
          end

          exports_dir = project.exports_directory
          has_local_exports = exports_dir.exist? && exports_dir.glob("**/*.png").any?
          has_cloud_exports = project.screenshot_exports.joins(:image_attachment).any?
          unless has_local_exports || has_cloud_exports
            exports_error = "No exported screenshots found for this project"
            next
          end

          # Guard: reject if a pending/in_progress upload exists for the project.
          # Uploads share the same export files, so concurrent project uploads can race.
          if ScreenshotUpload.active_for_project?(organization_id: @organization.id, screenshot_project_id: project.id)
            conflict_error = "An upload is already in progress for this project"
            next
          end

          upload = @organization.screenshot_uploads.new(
            screenshot_project: project,
            target: target,
            config: config
          )
          upload.save
        end

        if daily_limit_error
          return render_quota_exhausted(
            daily_limit_error,
            current_plan: @organization.plan_tier,
            next_plan: @organization.entitlements.next_plan_tier,
            suggestion: daily_limit_suggestion
          )
        end
        return render_invalid_request(exports_error) if exports_error
        return render json: { error: conflict_error }, status: :conflict if conflict_error

        if upload&.persisted?
          ScreenshotUploadJob.perform_later(upload.id)
          render json: { data: upload_json(upload) }, status: :created
        else
          render_validation_failed(upload&.errors&.full_messages&.join(", ") || "Failed to create upload")
        end
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def verify_read_scope
        verify_read_scope!
      end

      def verify_write_scope
        verify_write_scope!
      end

      def upload_json(upload)
        {
          id: upload.id,
          project_id: upload.screenshot_project_id,
          target: upload.target,
          status: upload.status,
          config: upload.config,
          progress: upload.progress,
          started_at: upload.started_at&.iso8601,
          completed_at: upload.completed_at&.iso8601,
          created_at: upload.created_at.iso8601,
          updated_at: upload.updated_at.iso8601
        }
      end

      def normalize_store_upload_config(project:, target:, config:)
        normalized = config.to_h.stringify_keys
        allowed_locales = Array(project.locales).map(&:to_s).map(&:strip).reject(&:blank?).uniq
        default_locale = project.default_locale.to_s

        # Handle batch-locale upload: expand all_locales into the locales array
        if normalized.delete("all_locales").present? && allowed_locales.size > 1
          normalized["locales"] = allowed_locales
        end

        locale_key = target == "app_store_connect" ? "locale" : "language"
        valid_locales = target == "google_play" ? ScreenshotProject::GOOGLE_PLAY_LOCALES : ScreenshotProject::APP_STORE_LOCALES

        if normalized["locales"].present?
          # Batch-locale mode: validate all locales
          normalized["locales"].each do |loc|
            unless valid_locales.include?(loc)
              return [ nil, "Unsupported #{locale_key}: #{loc}." ]
            end
          end
          # Remove single locale/language key when using batch mode
          normalized.delete(locale_key)
        else
          # Single-locale mode (existing behavior)
          locale_value = normalized[locale_key].to_s.strip
          locale_value = default_locale if locale_value.blank?

          unless valid_locales.include?(locale_value)
            return [ nil, "Unsupported #{locale_key}: #{locale_value}." ]
          end

          if allowed_locales.any? && !allowed_locales.include?(locale_value)
            return [ nil, "#{locale_key.capitalize} must be one of this project's locales: #{allowed_locales.join(', ')}" ]
          end

          normalized[locale_key] = locale_value
        end

        [ normalized, nil ]
      end

      def ensure_project_plan_access!
        project_id = params[:project_id] || params[:screenshot_project_id]
        project = @organization.screenshot_projects.find_by(id: project_id)
        return render_not_found("Screenshot project") unless project
        return if project.plan_accessible_on_current_plan?

        render json: {
          error: "plan_frozen",
          message: project.plan_frozen_reason || "This screenshot project is frozen on the current plan.",
          current_plan: @organization.plan_tier.to_s,
          project_id: project.id,
          project_name: project.name,
          plan_access_state: project.plan_access_state,
          frozen_project_ids: ScreenshotProject.plan_frozen_ids_for(@organization),
          accessible_project_ids: ScreenshotProject.plan_accessible_ids_for(@organization),
          suggestion: "Keep the oldest screenshot projects on the current plan or upgrade to unlock this project.",
          timestamp: Time.current.iso8601
        }, status: :forbidden
      end
    end
  end
end
