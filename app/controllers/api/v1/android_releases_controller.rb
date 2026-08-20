module Api
  module V1
    # CLI release defaults endpoint for Android — mirrors
    # Api::V1::AppStoreReleasesController but backed by the
    # `android_apps.cli_defaults` JSONB column.
    #
    # The `mysigner ship android` CLI reads from this endpoint at submission
    # time and layers its own --flag overrides on top.
    class AndroidReleasesController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :set_android_app, only: [ :show, :update, :destroy ]
      before_action :verify_read_scope, only: [ :index, :show ]
      before_action :verify_write_scope, only: [ :create, :update, :destroy ]

      # GET /api/v1/organizations/:organization_id/android_releases
      # Optional: ?package_name=com.example.app
      def index
        authorize @organization, :show?

        if params[:package_name].present?
          app = @organization.android_apps.find_by(package_name: params[:package_name])
          if app.nil? || !app.cli_defaults_configured?
            return render_not_found("Android releases", details: { package_name: params[:package_name] })
          end
          render json: { android_releases: [ app.cli_defaults_api_payload ] }
        else
          apps = @organization.android_apps.with_cli_defaults.order(updated_at: :desc)
          render json: { android_releases: apps.map(&:cli_defaults_api_payload) }
        end
      end

      # GET /api/v1/organizations/:organization_id/android_releases/:id
      def show
        authorize @organization, :show?
        render json: @android_app.cli_defaults_api_payload
      end

      # POST /api/v1/organizations/:organization_id/android_releases
      # Body: { android_release: { package_name: "com.example.app", default_track:, ... } }
      def create
        authorize @organization, :manage_resources?

        package_name = params.dig(:android_release, :package_name)
        android_app = @organization.android_apps.find_by(package_name: package_name) if package_name.present?

        if android_app.nil?
          return render_not_found("Android app", details: { reason: "No AndroidApp matches package_name #{package_name}" })
        end

        if android_app.cli_defaults_configured?
          return render_conflict(
            "A release configuration already exists for this package name. Use PATCH to update it.",
            resource_id: android_app.id
          )
        end

        if android_app.update_cli_defaults(permitted_cli_params)
          render json: android_app.reload.cli_defaults_api_payload, status: :created
        else
          render_validation_failed(
            "Failed to create Android release",
            details: android_app.cli_defaults_errors.map { |field, message| "#{field.to_s.humanize} #{message}" }
          )
        end
      end

      # PATCH /api/v1/organizations/:organization_id/android_releases/:id
      def update
        authorize @organization, :manage_resources?

        if @android_app.update_cli_defaults(permitted_cli_params)
          render json: @android_app.reload.cli_defaults_api_payload
        else
          render_validation_failed(
            "Failed to update Android release",
            details: @android_app.cli_defaults_errors.map { |field, message| "#{field.to_s.humanize} #{message}" }
          )
        end
      end

      # DELETE /api/v1/organizations/:organization_id/android_releases/:id
      # Clears cli_defaults — restores the "no defaults configured" state.
      def destroy
        authorize @organization, :manage_resources?
        @android_app.update!(cli_defaults: {})
        render json: { message: "CLI defaults cleared for #{@android_app.package_name}" }
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_android_app
        @android_app = @organization.android_apps.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Android release")
      end

      def verify_read_scope
        verify_read_scope!
      end

      def verify_write_scope
        verify_write_scope!
      end

      # Whitelists just the CLI-default keys. `release_notes` and
      # `country_targeting` are free-form hashes — strong params can't
      # declaratively permit them, so we extract and merge back after the
      # scalar permit (mirrors AppStoreReleasesController#permitted_cli_params).
      def permitted_cli_params
        return {} unless params[:android_release].is_a?(ActionController::Parameters) || params[:android_release].is_a?(Hash)

        scalar_params = params.require(:android_release).permit(
          :default_track,
          :default_status,
          :default_user_fraction,
          :default_in_app_update_priority,
          :changes_not_sent_for_review,
          :release_name
        ).to_h

        release_notes = params.dig(:android_release, :release_notes)
        if release_notes.respond_to?(:to_unsafe_h)
          scalar_params[:release_notes] = release_notes.to_unsafe_h
        elsif release_notes.is_a?(Hash)
          scalar_params[:release_notes] = release_notes
        end

        country_targeting = params.dig(:android_release, :country_targeting)
        if country_targeting.respond_to?(:to_unsafe_h)
          scalar_params[:country_targeting] = country_targeting.to_unsafe_h
        elsif country_targeting.is_a?(Hash)
          scalar_params[:country_targeting] = country_targeting
        end

        scalar_params
      end
    end
  end
end
