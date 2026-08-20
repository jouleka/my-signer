# frozen_string_literal: true

module Api
  module V1
    # Controller for managing app-level metadata (appInfo/appInfoLocalizations)
    # This includes subtitle, name, privacy info, etc. that live on the app, not the version.
    # Keywords are actually part of appStoreVersionLocalizations, not appInfoLocalizations,
    # but this controller provides a convenient endpoint for updating app-level metadata.
    class AppInfoController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :set_apple_app
      before_action :verify_read_scope, only: [ :show ]
      before_action :verify_write_scope, only: [ :update ]

      # GET /api/v1/organizations/:organization_id/apple_apps/:apple_app_id/app_info
      def show
        authorize @organization, :show?

        credential = active_credential
        return unless credential

        begin
          app_info_service = app_info_service_for(credential)
          app_info = app_info_service.primary(app_id: @apple_app.app_store_id)

          unless app_info
            return render_not_found("App info")
          end

          localizations = app_info_service.localizations(app_info_id: app_info["id"])

          render json: {
            data: {
              app_info_id: app_info["id"],
              state: app_info.dig("attributes", "state"),
              localizations: localizations.map { |loc| localization_json(loc) }
            }
          }
        rescue StandardError => e
          Rails.logger.error("Failed to fetch app info: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
          render_operation_failed("Failed to fetch app info: #{sanitize_error_message(e)}")
        end
      end

      # PATCH /api/v1/organizations/:organization_id/apple_apps/:apple_app_id/app_info
      # Params: locale, subtitle, name, privacy_policy_text, privacy_choices_url, privacy_policy_url
      def update
        authorize @organization, :manage_resources?

        credential = active_credential
        return unless credential

        locale = params[:locale].presence || @apple_app&.primary_locale || "en-US"
        update_attrs = update_params.to_h.symbolize_keys

        if update_attrs.empty?
          return render_invalid_request("No attributes provided to update")
        end

        begin
          app_info_service = app_info_service_for(credential)
          result = app_info_service.update_by_locale(
            app_id: @apple_app.app_store_id,
            locale: locale,
            **update_attrs
          )

          render json: {
            data: localization_json(result["data"]),
            message: "App info updated successfully"
          }
        rescue StandardError => e
          Rails.logger.error("Failed to update app info: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
          render_operation_failed("Failed to update app info: #{sanitize_error_message(e)}")
        end
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_apple_app
        # Note: params[:id] refers to the apple_app.id (our internal ID), not Apple's app_store_id
        @apple_app = @organization.apple_apps.find(params[:apple_app_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Apple app")
      end

      def active_credential
        credential = @organization.app_store_connect_credentials.find_by(active: true)
        unless credential
          render_credentials_required(
            "No active App Store Connect credential found",
            suggestion: "Please add one in Settings"
          )
          return nil
        end
        credential
      end

      def app_info_service_for(credential)
        apple_client = AppStoreConnect::Client.new(credential: credential)
        AppStoreConnect::AppInfo.new(apple_client)
      end

      def verify_read_scope
        verify_read_scope!
      end

      def verify_write_scope
        verify_write_scope!
      end

      def update_params
        params.permit(:subtitle, :name, :privacy_policy_text, :privacy_choices_url, :privacy_policy_url)
      end

      def localization_json(loc)
        return nil unless loc
        attrs = loc["attributes"] || {}
        {
          id: loc["id"],
          locale: attrs["locale"],
          name: attrs["name"],
          subtitle: attrs["subtitle"],
          privacy_policy_text: attrs["privacyPolicyText"],
          privacy_choices_url: attrs["privacyChoicesUrl"],
          privacy_policy_url: attrs["privacyPolicyUrl"]
        }
      end
    end
  end
end
