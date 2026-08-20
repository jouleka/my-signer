module Api
  module V1
    class OrganizationsController < ApplicationController
      # Phase 0: :credentials action removed (aggregate credential leak).
      # Filters no longer reference :credentials — Rails raises ActionNotFound
      # if a before_action :only option lists a non-existent action.
      before_action :set_organization, only: [ :show, :status, :sync_app_store_connect, :sync_google_play, :sync_status, :sync_status_google_play, :sync_all, :sync_status_all, :validate ]
      before_action :verify_token_organization_access!, only: [ :show, :status, :sync_app_store_connect, :sync_google_play, :sync_status, :sync_status_google_play, :sync_all, :sync_status_all, :validate ]
      before_action :verify_read_scope, only: [ :index, :show, :status, :sync_status, :sync_status_google_play, :sync_status_all, :validate ]
      before_action :verify_write_or_admin_scope, only: [ :sync_app_store_connect, :sync_google_play, :sync_all ]

      # GET /api/v1/organizations
      # Returns all organizations the current user has access to
      # Note: With org-specific tokens, this will only return the token's organization
      def index
        @organizations = policy_scope(Organization)

        # If using token auth, filter to only the token's organization
        if @current_api_token.present? && @token_organization_id.present?
          @organizations = @organizations.where(id: @token_organization_id)
        end

        render json: {
          organizations: @organizations.map do |org|
            {
              id: org.id,
              name: org.name,
              member_count: org.memberships.count,
              role: membership_role(org),
              access_state: org.access_state,
              plan: organization_plan_payload(org)
            }
          end,
          total: @organizations.count
        }
      end

      # GET /api/v1/organizations/:id
      # Returns detailed information about a specific organization
      def show
        authorize @organization

        credential = @organization.app_store_connect_credentials.where(active: true).first
        gp_credential = @organization.google_play_credentials.where(active: true).first

        response = {
          id: @organization.id,
          name: @organization.name,
          member_count: @organization.memberships.count,
          role: membership_role(@organization),
          access_state: @organization.access_state,
          plan: organization_plan_payload(@organization),
          stats: organization_stats(@organization),
          sync: organization_sync_info(@organization),
          app_store_connect_configured: credential.present?,
          google_play_configured: gp_credential.present?,
          credentials_status: credentials_status(credential),
          created_at: @organization.created_at.iso8601,
          updated_at: @organization.updated_at.iso8601
        }

        # Include token_organization_id if using token auth (for CLI org detection)
        if @current_api_token.present?
          response[:token_organization_id] = @token_organization_id
        end

        render json: response
      end

      # Phase 0 hard removal: GET /api/v1/organizations/:id/credentials is
      # REMOVED. It used to return ASC private key + Google Play service
      # account JSON in one response — a single-token credential leak.
      # Replaced by narrow per-purpose endpoints:
      #   POST /credentials/google_play/access_token   (short-lived OAuth2)
      #   POST /android_keystores/:id/secrets          (audit-logged)
      # plus the full /builds/asc_upload REST flow for iOS uploads so the
      # .p8 never leaves the server at all.
      # (The route is deleted in config/routes.rb — this 410 handler is a
      # belt-and-suspenders fallback for any caller that somehow reaches
      # here via a cached route or stale CLI.)

      # GET /api/v1/organizations/:id/status
      # Returns health check and statistics for the organization
      def status
        authorize @organization

        render json: {
          id: @organization.id,
          name: @organization.name,
          status: "ok",
          access_state: @organization.access_state,
          plan: organization_plan_payload(@organization),
          stats: organization_stats(@organization),
          sync: organization_sync_info(@organization),
          timestamp: Time.current.iso8601
        }
      end

      # POST /api/v1/organizations/:id/sync_app_store_connect
      # Triggers a background sync with App Store Connect
      def sync_app_store_connect
        authorize @organization, :sync?

        unless @organization.app_store_connect_credentials.find_by(active: true)
          return render_credentials_required("No active App Store Connect credential found")
        end

        force = ActiveModel::Type::Boolean.new.cast(params[:force])
        result = enqueue_app_store_connect_sync(@organization, force: force, min_interval: AutoSync::SYNC_MANUAL_MIN_INTERVAL)

        case result
        when :enqueued
          render json: {
            message: "Sync enqueued successfully",
            enqueued: true,
            organization_id: @organization.id,
            timestamp: Time.current.iso8601
          }, status: :accepted
        when :running
          render json: { message: "Sync already running", enqueued: false, organization_id: @organization.id }, status: :accepted
        when :fresh
          render json: { message: "Already synced recently. Use force=true to sync anyway.", enqueued: false, organization_id: @organization.id }, status: :ok
        when :cooldown
          render json: { message: "Sync was just queued. Please wait before retrying.", enqueued: false, organization_id: @organization.id }, status: :too_many_requests
        else
          render_credentials_required("No active App Store Connect credential found")
        end
      rescue => e
        Rails.logger.error("Sync failed: #{e.class} - #{e.message}")
        Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
        render_operation_failed("Sync failed: #{sanitize_error_message(e)}")
      end

      def sync_google_play
        authorize @organization, :sync?

        unless @organization.google_play_credentials.find_by(active: true)
          return render_credentials_required("No active Google Play credential found")
        end

        force = ActiveModel::Type::Boolean.new.cast(params[:force])
        result = enqueue_google_play_sync(@organization, force: force, min_interval: AutoSync::SYNC_MANUAL_MIN_INTERVAL)

        case result
        when :enqueued
          render json: {
            message: "Sync enqueued successfully",
            enqueued: true,
            organization_id: @organization.id,
            timestamp: Time.current.iso8601
          }, status: :accepted
        when :running
          render json: { message: "Sync already running", enqueued: false, organization_id: @organization.id }, status: :accepted
        when :fresh
          render json: { message: "Already synced recently. Use force=true to sync anyway.", enqueued: false, organization_id: @organization.id }, status: :ok
        when :cooldown
          render json: { message: "Sync was just queued. Please wait before retrying.", enqueued: false, organization_id: @organization.id }, status: :too_many_requests
        else
          render_credentials_required("No active Google Play credential found")
        end
      rescue => e
        Rails.logger.error("Sync failed: #{e.class} - #{e.message}")
        Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
        render_operation_failed("Sync failed: #{sanitize_error_message(e)}")
      end

      # GET /api/v1/organizations/:id/sync/status
      # Returns current sync status and history
      def sync_status
        authorize @organization, :sync?

        running = sync_lock_present?(@organization.id)
        credential = @organization.app_store_connect_credentials.order(last_synced_at: :desc).first

        render json: {
          organization_id: @organization.id,
          sync: {
            running: running,
            last_synced_at: credential&.last_synced_at&.iso8601,
            last_sync_status: credential&.last_sync_status || "never",
            last_sync_error: credential&.last_sync_error
          },
          timestamp: Time.current.iso8601
        }
      end

      def sync_status_google_play
        authorize @organization, :sync?

        running = gp_sync_lock_present?(@organization.id)
        credential = @organization.google_play_credentials.order(last_synced_at: :desc).first

        render json: {
          organization_id: @organization.id,
          running: running,
          last_synced_at: credential&.last_synced_at&.iso8601,
          last_sync_status: credential&.last_sync_status || "never",
          last_sync_error: credential&.last_sync_error,
          timestamp: Time.current.iso8601
        }
      end

      # POST /api/v1/organizations/:id/sync_all
      # Triggers the unified sync orchestrator (ASC + GP + reviews + analytics + CPP + keywords)
      def sync_all
        authorize @organization, :sync?
        force = ActiveModel::Type::Boolean.new.cast(params[:force])
        dispatched = Sync::OrchestratorDispatcher.new(organization: @organization, force: force).call

        Audit::Logger.log(
          action: "sync_all_triggered",
          organization: @organization,
          actor: current_user,
          metadata: { dispatched: dispatched.transform_values(&:to_s) },
          request: request
        )

        render json: {
          dispatched: dispatched,
          organization_id: @organization.id,
          timestamp: Time.current.iso8601
        }, status: :accepted
      end

      # GET /api/v1/organizations/:id/sync_status_all
      # Returns the composite status across all sync jobs
      def sync_status_all
        authorize @organization, :sync?
        render json: Sync::StatusAggregator.new(organization: @organization).payload
      end

      # POST /api/v1/organizations/:id/validate
      # Validates if a project can be signed with current resources
      def validate
        authorize @organization

        bundle_id_param = params[:bundle_id]
        type_param = params[:type]

        # Validate required parameters
        if bundle_id_param.blank?
          return render_invalid_request("Parameter 'bundle_id' is required")
        end

        if type_param.blank?
          return render_invalid_request("Parameter 'type' is required")
        end

        # Normalize profile type (support user-friendly aliases)
        profile_type = normalize_profile_type(type_param)
        unless profile_type
          return render_invalid_request("Invalid type '#{type_param}'. Valid types: development, appstore, adhoc, inhouse")
        end

        # Run validation checks
        validation_result = validate_signing_resources(bundle_id_param, profile_type)

        if validation_result[:valid]
          render json: {
            valid: true,
            message: "All required resources are available for signing",
            bundle_id: bundle_id_param,
            type: profile_type,
            checks: validation_result[:checks]
          }, status: :ok
        else
          render json: {
            valid: false,
            message: "Missing or invalid resources required for signing",
            bundle_id: bundle_id_param,
            type: profile_type,
            checks: validation_result[:checks],
            suggestions: validation_result[:suggestions]
          }, status: :ok
        end
      end

      private

      def credentials_status(credential)
        {
          configured: credential.present?,
          team_id_set: credential&.team_id.present?,
          needs_setup: !credential.present?
        }
      end

      def set_organization
        @organization = Organization.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def verify_read_scope
        verify_read_scope!
      end

      def verify_write_or_admin_scope
        verify_write_scope!
      end

      def verify_admin_scope_for_credentials
        verify_admin_scope!
      end

      def organization_stats(org)
        {
          certificates_count: org.apple_certificates.count,
          devices_count: org.apple_devices.count,
          profiles_count: org.apple_provisioning_profiles.count,
          invalid_profiles_count: org.apple_provisioning_profiles.where(state: "INVALID").count,
          bundle_ids_count: org.apple_bundle_ids.count
        }
      end

      def organization_sync_info(org)
        credential = org.app_store_connect_credentials.where(active: true).first

        if credential
          {
            status: "ok",
            last_synced_at: credential.last_synced_at&.iso8601,
            has_credentials: true
          }
        else
          {
            status: "no_credentials",
            last_synced_at: nil,
            has_credentials: false
          }
        end
      end

      def membership_role(org)
        # Show "owner" if user is the organization owner
        return "owner" if org.owner_id == current_user.id

        membership = org.memberships.find_by(user_id: current_user.id)
        membership&.role || "viewer"
      end

      def normalize_profile_type(type)
        case type.to_s.downcase.strip
        when "development", "dev"
          "IOS_APP_DEVELOPMENT"
        when "appstore", "store", "app-store"
          "IOS_APP_STORE"
        when "adhoc", "ad-hoc"
          "IOS_APP_ADHOC"
        when "inhouse", "enterprise"
          "IOS_APP_INHOUSE"
        else
          nil
        end
      end

      def validate_signing_resources(bundle_id_identifier, profile_type)
        checks = {}
        suggestions = []

        # Check 1: Bundle ID exists
        bundle_id = @organization.apple_bundle_ids.find_by(identifier: bundle_id_identifier)
        checks[:bundle_id] = {
          status: bundle_id.present? ? "pass" : "fail",
          message: bundle_id.present? ? "Bundle ID '#{bundle_id_identifier}' exists" : "Bundle ID '#{bundle_id_identifier}' not found"
        }

        if bundle_id.nil?
          suggestions << "Register bundle ID '#{bundle_id_identifier}' in App Store Connect"
        end

        # Check 2: Valid certificate exists
        cert_types = certificate_type_for_profile(profile_type)
        valid_cert = @organization.apple_certificates
          .where(certificate_type: cert_types)
          .where("expires_at > ?", Time.current)
          .first

        checks[:certificate] = {
          status: valid_cert.present? ? "pass" : "fail",
          message: valid_cert.present? ? "Valid #{cert_types.first} certificate exists" : "No valid #{cert_types.join('/')} certificate found",
          type: cert_types.first
        }

        if valid_cert.nil?
          suggestions << "Create or sync a valid #{cert_types.join('/')} certificate"
        end

        # Check 3: Matching profile exists
        matching_profile = @organization.apple_provisioning_profiles
          .where(bundle_id_identifier: bundle_id_identifier, profile_type: profile_type, state: "ACTIVE")
          .where("expires_at > ?", Time.current)
          .first

        checks[:profile] = {
          status: matching_profile.present? ? "pass" : "fail",
          message: matching_profile.present? ? "Valid provisioning profile exists" : "No valid provisioning profile found",
          profile_id: matching_profile&.id,
          profile_name: matching_profile&.name
        }

        if matching_profile.nil?
          suggestions << "Create a #{profile_type} provisioning profile for bundle ID '#{bundle_id_identifier}'"
        end

        # Overall validation result
        all_passed = checks.values.all? { |check| check[:status] == "pass" }

        {
          valid: all_passed,
          checks: checks,
          suggestions: suggestions
        }
      end

      def certificate_type_for_profile(profile_type)
        case profile_type
        when "IOS_APP_DEVELOPMENT"
          [ "DEVELOPMENT", "IOS_DEVELOPMENT", "IOS_APP_DEVELOPMENT" ]
        when "IOS_APP_STORE", "IOS_APP_ADHOC", "IOS_APP_INHOUSE"
          [ "DISTRIBUTION", "IOS_DISTRIBUTION", "IOS_APP_DISTRIBUTION" ]
        else
          [ "DEVELOPMENT", "IOS_DEVELOPMENT", "IOS_APP_DEVELOPMENT" ]
        end
      end
    end
  end
end
