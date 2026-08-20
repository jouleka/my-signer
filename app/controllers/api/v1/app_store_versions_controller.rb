module Api
  module V1
    class AppStoreVersionsController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :set_version, only: [ :show, :update, :attach_build, :submit, :phased_release ]
      before_action :verify_read_scope, only: [ :index, :show ]
      before_action :verify_write_scope, only: [ :create, :update, :attach_build, :submit, :phased_release ]

      # GET /api/v1/organizations/:organization_id/app_store_versions
      # Params: app_id, editable (bool)
      def index
        authorize @organization, :show?

        scope = @organization.app_store_versions

        if params[:app_id].present?
          scope = scope.where(apple_app_id: params[:app_id])
        end

        if params[:editable].to_s == "true"
          scope = scope.editable
        end

        # Pagination
        page = [ params[:page].to_i, 1 ].max
        per_page = [ [ params[:per_page].to_i, 1 ].max, 100 ].min
        per_page = 50 if per_page == 1 && params[:per_page].blank?

        total = scope.count
        versions = scope.order(created_at: :desc).offset((page - 1) * per_page).limit(per_page)

        render json: {
          data: {
            versions: versions.map { |v| version_json(v) }
          },
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            total_pages: (total.to_f / per_page).ceil
          }
        }
      end

      # GET /api/v1/organizations/:organization_id/app_store_versions/:id
      def show
        authorize @organization, :show?
        render json: { data: version_json(@version) }
      end

      # POST /api/v1/organizations/:organization_id/app_store_versions
      def create
        authorize @organization, :manage_resources?

        app = @organization.apple_apps.find_by(id: version_params[:app_id])
        unless app
          return render_not_found("App")
        end

        credential = @organization.app_store_connect_credentials.find_by(active: true)
        unless credential
          return render_credentials_required(
            "No active App Store Connect credential found",
            suggestion: "Please add one in Settings"
          )
        end

        begin
          # Check Apple for existing editable versions first
          apple_client = AppStoreConnect::Client.new(credential: credential)
          versions_service = AppStoreConnect::Versions.new(apple_client)

          editable_versions = versions_service.editable_versions(app_id: app.app_store_id)

          apple_version = nil
          if editable_versions.any?
            # Reuse existing editable version
            apple_version = editable_versions.first
          else
            # Parse earliest_release_date if provided
            earliest = version_params[:earliest_release_date]
            if earliest.present?
              earliest = Time.zone.parse(earliest) if earliest.is_a?(String)
              earliest = earliest.utc
            end

            # Create new version in Apple
            apple_response = versions_service.create(
              app_id: app.app_store_id,
              version_string: version_params[:version_string],
              platform: version_params[:platform] || "IOS",
              release_type: version_params[:release_type] || "AFTER_APPROVAL",
              earliest_release_date: earliest
            )
            apple_version = apple_response["data"]
          end

          apple_version_id = apple_version["id"]
          apple_state = apple_version.dig("attributes", "appStoreState")
          version_string = apple_version.dig("attributes", "versionString")

          # Check if we already have this version in our DB
          existing_version = @organization.app_store_versions.find_by(version_id: apple_version_id)

          if existing_version
            # Return existing version
            render json: { data: version_json(existing_version) }, status: :ok
          else
            # Store new version in our database with Apple's version_id
            version = @organization.app_store_versions.new(
              apple_app: app,
              version_id: apple_version_id,
              version_string: version_string,
              platform: version_params[:platform] || "IOS",
              app_store_state: apple_state || "PREPARE_FOR_SUBMISSION",
              raw_json: apple_version
            )

            if version.save
              render json: { data: version_json(version) }, status: :created
            else
              render_validation_failed(version.errors.full_messages.join(", "))
            end
          end
        rescue StandardError => e
          Rails.logger.error("Failed to create version in Apple: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
          render_operation_failed("Failed to create version in Apple: #{sanitize_error_message(e)}")
        end
      end

      # PATCH /api/v1/organizations/:organization_id/app_store_versions/:id
      def update
        authorize @organization, :manage_resources?

        if @version.update(update_params)
          render json: { data: version_json(@version) }
        else
          render_validation_failed(@version.errors.full_messages.join(", "))
        end
      end

      # POST /api/v1/organizations/:organization_id/app_store_versions/:id/build
      def attach_build
        authorize @organization, :manage_resources?

        build = @organization.apple_builds.find_by(id: params[:build_id])
        unless build
          return render_not_found("Build")
        end

        credential = @organization.app_store_connect_credentials.find_by(active: true)
        unless credential
          return render_credentials_required(
            "No active App Store Connect credential found",
            suggestion: "Please add one in Settings"
          )
        end

        begin
          # Attach build in Apple
          apple_client = AppStoreConnect::Client.new(credential: credential)
          versions_service = AppStoreConnect::Versions.new(apple_client)

          # Use the Apple build_id (stored in our build_id column from sync)
          versions_service.attach_build(
            version_id: @version.version_id,
            build_id: build.build_id
          )

          # Update our local relationship
          @version.update!(apple_build: build)

          render json: { data: version_json(@version) }
        rescue StandardError => e
          Rails.logger.error("Failed to attach build in Apple: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
          render_operation_failed("Failed to attach build in Apple: #{sanitize_error_message(e)}")
        end
      end

      # POST /api/v1/organizations/:organization_id/app_store_versions/:id/submit
      # Params: whats_new, marketing_url, promotional_text, support_url (optional metadata)
      # Note: keywords are deprecated in appStoreVersionLocalizations - use AppInfoController for app-level metadata
      def submit
        authorize @organization, :manage_resources?

        unless @version.apple_build
          return render_precondition_failed(
            "Cannot submit without a build attached",
            suggestion: "Please attach a build first"
          )
        end

        credential = @organization.app_store_connect_credentials.find_by(active: true)
        unless credential
          return render_credentials_required(
            "No active App Store Connect credential found",
            suggestion: "Please add one in Settings"
          )
        end

        begin
          # Update localization(s) if metadata provided
          apple_client = AppStoreConnect::Client.new(credential: credential)
          versions_service = AppStoreConnect::Versions.new(apple_client)

          # Collect requested localizations. Two accepted shapes:
          #   (a) primary-locale-only (legacy): top-level whats_new/keywords/
          #       marketing_url/support_url/promotional_text/description with
          #       params[:locale] defaulting to primary_locale.
          #   (b) multi-locale: params[:localizations] = [{locale, whats_new,
          #       keywords, marketing_url, promotional_text, support_url,
          #       description}, ...] — sent by CLI when dashboard
          #       `cli_defaults.localizations` is configured.
          requested_localizations = []

          if params[:localizations].is_a?(Array)
            requested_localizations.concat(
              params[:localizations].filter_map do |loc|
                next nil if loc.blank? || loc[:locale].blank?
                {
                  locale:           loc[:locale],
                  whats_new:        loc[:whats_new],
                  keywords:         loc[:keywords],
                  marketing_url:    loc[:marketing_url],
                  promotional_text: loc[:promotional_text],
                  support_url:      loc[:support_url],
                  description:      loc[:description]
                }
              end
            )
          end

          if params[:whats_new].present? || params[:marketing_url].present? || params[:support_url].present? || params[:promotional_text].present? || params[:description].present? || params[:keywords].present?
            primary = {
              locale:           params[:locale].presence || @version&.apple_app&.primary_locale || "en-US",
              whats_new:        params[:whats_new],
              keywords:         params[:keywords],
              marketing_url:    params[:marketing_url],
              promotional_text: params[:promotional_text],
              support_url:      params[:support_url],
              description:      params[:description]
            }
            # Only add primary if a locale-matching entry isn't already in the
            # multi-locale array (avoid double-writing the same locale).
            unless requested_localizations.any? { |l| l[:locale] == primary[:locale] }
              requested_localizations << primary
            end
          end

          if requested_localizations.any?
            existing_localizations = versions_service.localizations(version_id: @version.version_id)
            requested_localizations.each do |req|
              existing = existing_localizations.find { |loc| loc.dig("attributes", "locale") == req[:locale] }
              if existing
                versions_service.update_localization(
                  localization_id: existing["id"],
                  description:     req[:description],
                  keywords:        req[:keywords],
                  whats_new:       req[:whats_new],
                  marketing_url:   req[:marketing_url],
                  promotional_text: req[:promotional_text],
                  support_url:     req[:support_url]
                )
              else
                versions_service.create_localization(
                  version_id:      @version.version_id,
                  locale:          req[:locale],
                  description:     req[:description],
                  keywords:        req[:keywords],
                  whats_new:       req[:whats_new],
                  marketing_url:   req[:marketing_url],
                  promotional_text: req[:promotional_text],
                  support_url:     req[:support_url]
                )
              end
            end
          end

          # Submit using the Apple version_id (not our internal ID)
          # Need to pass the app_store_id from the associated apple_app
          versions_service.submit_for_review(
            app_id: @version.apple_app.app_store_id,
            version_id: @version.version_id
          )

          # Update our local state
          @version.update!(app_store_state: "WAITING_FOR_REVIEW")

          # Auto-trigger phased release if requested
          phased_release_message = nil
          if ActiveModel::Type::Boolean.new.cast(params[:phased_release])
            @version.update!(phased_release_pending: true)
            PhasedReleaseActivationJob.perform_later(@version.id)
            phased_release_message = "Phased release will be activated after app approval."
          end

          message = "Version submitted for App Store review"
          message += " #{phased_release_message}" if phased_release_message

          render json: {
            data: version_json(@version),
            message: message
          }
        rescue StandardError => e
          # If submission failed, try to fetch validation errors from Apple
          validation_errors = []
          begin
            validation_errors = versions_service.validation_errors(version_id: @version.version_id)
            Rails.logger.info("Validation errors fetched: #{validation_errors.inspect}")
          rescue => fetch_error
            Rails.logger.error("Failed to fetch validation errors: #{fetch_error.message}")
            Rails.logger.error(fetch_error.backtrace.join("\n"))
          end

          error_message = "Failed to submit to Apple: #{sanitize_error_message(e)}"

          # Check if this is a "not in valid state" error (usually first-time submission missing metadata)
          if e.message.include?("not in valid state") || e.message.include?("cannot be reviewed")
            error_message += "\n\n⚠️  This usually means required metadata is missing in App Store Connect."
            error_message += "\n\nFor first-time submissions, you must configure these in the App Store Connect UI:"
            error_message += "\n  • Screenshots (at least one set)"
            error_message += "\n  • App Description"
            error_message += "\n  • Keywords"
            error_message += "\n  • Age Rating (complete questionnaire)"
            error_message += "\n  • Privacy Policy URL (if app collects data)"
            error_message += "\n  • App Icon"
            error_message += "\n\nVisit: https://appstoreconnect.apple.com"
            error_message += "\nNavigate to: Your App → Prepare for Submission"
            error_message += "\n\nAfter configuring metadata once, subsequent builds can be submitted via CLI."
          elsif validation_errors.any?
            error_message += "\n\nValidation errors:\n#{validation_errors.map { |err| "  - #{err}" }.join("\n")}"
          end

          Rails.logger.error("Submission error: #{error_message}")

          render_operation_failed(error_message, details: { validation_errors: validation_errors })
        end
      end

      # POST /api/v1/organizations/:organization_id/app_store_versions/:id/phased_release
      # Params: action (activate, pause, resume, complete)
      def phased_release
        authorize @organization, :manage_resources?

        credential = @organization.app_store_connect_credentials.find_by(active: true)
        unless credential
          return render_credentials_required(
            "No active App Store Connect credential found",
            suggestion: "Please add one in Settings"
          )
        end

        action = params[:action_type]&.to_s&.downcase
        unless %w[activate pause resume complete].include?(action)
          return render_invalid_request("Invalid action. Must be one of: activate, pause, resume, complete")
        end

        begin
          apple_client = AppStoreConnect::Client.new(credential: credential)
          versions_service = AppStoreConnect::Versions.new(apple_client)

          case action
          when "activate"
            eligibility = versions_service.phased_release_eligibility(version_id: @version.version_id)

            case eligibility
            when :can_activate
              versions_service.create_phased_release(version_id: @version.version_id, state: "ACTIVE")
              @version.update!(phased_release_pending: false)
              render json: { data: version_json(@version), message: "Phased release activated" }
            when :already_active
              render json: { data: version_json(@version), message: "Phased release already active" }
            when :pending_review
              # Queue background job to activate after approval
              @version.update!(phased_release_pending: true)
              PhasedReleaseActivationJob.perform_later(@version.id)
              render json: { data: version_json(@version), message: "Phased release will be activated after app approval" }
            when :removed_from_sale
              render_invalid_state("Cannot activate phased release for removed app")
            else
              render_invalid_state("Version is not in a valid state for phased release")
            end
          when "pause"
            existing = versions_service.phased_release(version_id: @version.version_id)
            unless existing
              return render_not_found("Phased release", details: { reason: "No active phased release found" })
            end
            versions_service.update_phased_release(phased_release_id: existing["id"], state: "PAUSE")
            render json: { data: version_json(@version), message: "Phased release paused" }
          when "resume"
            existing = versions_service.phased_release(version_id: @version.version_id)
            unless existing
              return render_not_found("Phased release", details: { reason: "No active phased release found" })
            end
            versions_service.update_phased_release(phased_release_id: existing["id"], state: "ACTIVE")
            render json: { data: version_json(@version), message: "Phased release resumed" }
          when "complete"
            existing = versions_service.phased_release(version_id: @version.version_id)
            unless existing
              return render_not_found("Phased release", details: { reason: "No active phased release found" })
            end
            versions_service.update_phased_release(phased_release_id: existing["id"], state: "COMPLETE")
            render json: { data: version_json(@version), message: "Phased release completed - app now available to all users" }
          end
        rescue StandardError => e
          Rails.logger.error("Failed to manage phased release: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
          render_operation_failed("Failed to manage phased release: #{sanitize_error_message(e)}")
        end
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_version
        @version = @organization.app_store_versions.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Version")
      end

      def verify_read_scope
        verify_read_scope!
      end

      def verify_write_scope
        verify_write_scope!
      end

      def version_params
        params.require(:app_store_version).permit(
          :app_id, :version_string, :platform, :release_type, :earliest_release_date
        )
      end

      def update_params
        params.require(:app_store_version).permit(:version_string)
      end

      def version_json(version)
        {
          id: version.id,
          version_id: version.version_id,
          app_id: version.apple_app_id,
          build_id: version.apple_build_id,
          version_string: version.version_string,
          platform: version.platform,
          app_store_state: version.app_store_state,
          release_type: version.raw_json&.dig("attributes", "releaseType"),
          earliest_release_date: version.raw_json&.dig("attributes", "earliestReleaseDate"),
          phased_release_pending: version.phased_release_pending,
          created_at: version.created_at.iso8601,
          updated_at: version.updated_at.iso8601
        }
      end
    end
  end
end
