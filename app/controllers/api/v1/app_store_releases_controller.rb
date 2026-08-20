module Api
  module V1
    # CLI release defaults endpoint.
    #
    # Despite the route name (`app_store_releases`, kept for backward
    # compatibility with the `mysigner` CLI), this controller now operates on
    # the `apple_apps.cli_defaults` JSONB column — the legacy `AppStoreRelease`
    # model has been retired. The JSON response shape is preserved byte-for-byte
    # so the CLI does not need to change.
    #
    # The `id` in the single-record endpoints refers to `apple_apps.id`, not
    # a separate AppStoreRelease record ID. The CLI consumes `id` as an opaque
    # value it round-trips on PATCH, so this substitution is transparent.
    class AppStoreReleasesController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :set_apple_app, only: [ :show, :update ]
      before_action :verify_read_scope, only: [ :index, :show ]
      before_action :verify_write_scope, only: [ :create, :update ]

      # GET /api/v1/organizations/:organization_id/app_store_releases
      # Query params:
      #   - bundle_id: filter by bundle identifier (e.g., com.example.app)
      #
      # Returns 404 when no CLI defaults have been configured for the requested
      # bundle_id — preserving the behavior of the legacy AppStoreRelease-backed
      # implementation (the MySigner CLI's `fetch_release_metadata` rescues
      # NotFoundError and returns nil for unconfigured apps).
      def index
        authorize @organization, :show?

        if params[:bundle_id].present?
          app = @organization.apple_apps.find_by(bundle_id: params[:bundle_id])
          if app.nil? || !app.cli_defaults_configured?
            return render_not_found("App Store releases", details: { bundle_id: params[:bundle_id] })
          end

          render json: { app_store_releases: [ app.cli_defaults_api_payload ] }
        else
          apps = @organization.apple_apps.with_cli_defaults.order(updated_at: :desc)
          render json: {
            app_store_releases: apps.map(&:cli_defaults_api_payload)
          }
        end
      end

      # GET /api/v1/organizations/:organization_id/app_store_releases/:id
      # The :id here is an apple_apps.id (see class docstring).
      def show
        authorize @organization, :show?
        render json: @apple_app.cli_defaults_api_payload
      end

      # POST /api/v1/organizations/:organization_id/app_store_releases
      # Body: { app_store_release: { apple_bundle_id_id:, release_type:, ... } }
      #
      # The CLI identifies the target app by the apple_bundle_id record. We
      # resolve it to the matching AppleApp, then write cli_defaults and
      # optionally sync content fields to the primary-locale StoreListing.
      def create
        authorize @organization, :manage_resources?

        bundle_id_record = @organization.apple_bundle_ids.find_by(id: params.dig(:app_store_release, :apple_bundle_id_id))
        if bundle_id_record.nil?
          return render_not_found("Bundle ID")
        end

        apple_app = @organization.apple_apps.find_by(bundle_id: bundle_id_record.identifier)
        if apple_app.nil?
          return render_not_found("App", details: { reason: "No AppleApp matches bundle identifier #{bundle_id_record.identifier}" })
        end

        if apple_app.cli_defaults_configured?
          return render_conflict(
            "A release configuration already exists for this bundle ID. Use PATCH to update it.",
            resource_id: apple_app.id
          )
        end

        if apple_app.update_cli_defaults(permitted_cli_params)
          apple_app.sync_content_fields_to_store_listing(permitted_content_params)
          render json: apple_app.reload.cli_defaults_api_payload, status: :created
        else
          render_validation_failed(
            "Failed to create App Store release",
            details: apple_app.cli_defaults_errors.map { |field, message| "#{field.to_s.humanize} #{message}" }
          )
        end
      end

      # PATCH /api/v1/organizations/:organization_id/app_store_releases/:id
      def update
        authorize @organization, :manage_resources?

        if @apple_app.update_cli_defaults(permitted_cli_params)
          @apple_app.sync_content_fields_to_store_listing(permitted_content_params)
          render json: @apple_app.reload.cli_defaults_api_payload
        else
          render_validation_failed(
            "Failed to update App Store release",
            details: @apple_app.cli_defaults_errors.map { |field, message| "#{field.to_s.humanize} #{message}" }
          )
        end
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_apple_app
        @apple_app = @organization.apple_apps.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("App Store release")
      end

      def verify_read_scope
        verify_read_scope!
      end

      def verify_write_scope
        verify_write_scope!
      end

      # Returns only the CLI-default keys from the permitted params (the
      # AppleApp model is responsible for further normalization + validation).
      #
      # `localizations` is a JSONB field with no fixed schema, so strong
      # params can't declaratively permit it (scalar permits strip arrays,
      # and array permits of hashes require inner-key declarations). We
      # extract it manually and merge it back in after the normal permit.
      def permitted_cli_params
        return {} unless params[:app_store_release].is_a?(ActionController::Parameters) || params[:app_store_release].is_a?(Hash)

        scalar_params = params.require(:app_store_release).permit(
          :release_type,
          :earliest_release_date,
          :auto_submit,
          :phased_release,
          :version_string,
          :build_number
        ).to_h

        localizations = params.dig(:app_store_release, :localizations)
        if localizations.is_a?(Array)
          scalar_params[:localizations] = localizations.map do |item|
            item.respond_to?(:to_unsafe_h) ? item.to_unsafe_h : item
          end
        end

        scalar_params
      end

      # Returns only content keys (forwarded to the primary-locale StoreListing).
      def permitted_content_params
        return {} unless params[:app_store_release].is_a?(ActionController::Parameters) || params[:app_store_release].is_a?(Hash)
        params.require(:app_store_release).permit(
          :whats_new,
          :promotional_text,
          :support_url,
          :marketing_url,
          :privacy_policy_url
        )
      end
    end
  end
end
