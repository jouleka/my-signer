# frozen_string_literal: true

module Api
  module V1
    # Controller for managing App Store version localizations
    # Localizations include what's new text, marketing URL, promotional text, support URL
    # Keywords are part of appStoreVersionLocalizations (not appInfoLocalizations).
    # name and subtitle live on appInfoLocalizations.
    class AppStoreVersionLocalizationsController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :set_version
      before_action :verify_read_scope, only: [ :index ]
      before_action :verify_write_scope, only: [ :create, :update, :destroy ]
      before_action :normalize_localizations_params, only: [ :create, :update ]

      # GET /api/v1/organizations/:organization_id/app_store_versions/:app_store_version_id/localizations
      def index
        authorize @organization, :show?

        credential = active_credential
        return unless credential

        begin
          versions_service = versions_service_for(credential)
          localizations = versions_service.localizations(version_id: @version.version_id)

          render json: {
            data: {
              localizations: localizations.map { |loc| localization_json(loc) }
            }
          }
        rescue StandardError => e
          Rails.logger.error("Failed to fetch localizations: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
          render_operation_failed("Failed to fetch localizations: #{sanitize_error_message(e)}")
        end
      end

      # POST /api/v1/organizations/:organization_id/app_store_versions/:app_store_version_id/localizations
      # Params: locale, whats_new, marketing_url, promotional_text, support_url
      def create
        authorize @organization, :manage_resources?

        credential = active_credential
        return unless credential

        locale = params[:locale].presence || @version&.apple_app&.primary_locale || "en-US"

        begin
          versions_service = versions_service_for(credential)

          result = versions_service.create_localization(
            version_id: @version.version_id,
            locale: locale,
            description: params[:description],
            keywords: params[:keywords],
            whats_new: params[:whats_new],
            marketing_url: params[:marketing_url],
            promotional_text: params[:promotional_text],
            support_url: params[:support_url]
          )

          render json: {
            data: localization_json(result["data"]),
            message: "Localization created successfully"
          }, status: :created
        rescue StandardError => e
          Rails.logger.error("Failed to create localization: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
          render_operation_failed("Failed to create localization: #{sanitize_error_message(e)}")
        end
      end

      # PATCH /api/v1/organizations/:organization_id/app_store_versions/:app_store_version_id/localizations/:id
      # Params: whats_new, marketing_url, promotional_text, support_url
      # Note: params[:id] is Apple's localization ID (string), not a Rails model ID
      def update
        authorize @organization, :manage_resources?

        credential = active_credential
        return unless credential

        # params[:id] is the Apple localization ID (e.g., "abc123-def456")
        localization_id = params[:id]

        begin
          versions_service = versions_service_for(credential)

          # Verify the localization belongs to this version (prevents cross-version tampering)
          localizations = versions_service.localizations(version_id: @version.version_id)
          unless localizations.any? { |loc| loc["id"] == localization_id }
            return render_not_found("Localization")
          end

          result = versions_service.update_localization(
            localization_id: localization_id,
            description: params[:description],
            keywords: params[:keywords],
            whats_new: params[:whats_new],
            marketing_url: params[:marketing_url],
            promotional_text: params[:promotional_text],
            support_url: params[:support_url]
          )

          render json: {
            data: localization_json(result["data"]),
            message: "Localization updated successfully"
          }
        rescue StandardError => e
          Rails.logger.error("Failed to update localization: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
          render_operation_failed("Failed to update localization: #{sanitize_error_message(e)}")
        end
      end

      # DELETE /api/v1/organizations/:organization_id/app_store_versions/:app_store_version_id/localizations/:id
      # Note: params[:id] is Apple's localization ID (string), not a Rails model ID
      def destroy
        authorize @organization, :manage_resources?

        credential = active_credential
        return unless credential

        localization_id = params[:id]

        begin
          # Verify the localization belongs to this version (prevents cross-version tampering)
          versions_service = versions_service_for(credential)
          localizations = versions_service.localizations(version_id: @version.version_id)
          unless localizations.any? { |loc| loc["id"] == localization_id }
            return render_not_found("Localization")
          end

          apple_client = AppStoreConnect::Client.new(credential: credential)
          apple_client.delete("appStoreVersionLocalizations/#{localization_id}")

          render json: { message: "Localization deleted successfully" }
        rescue StandardError => e
          Rails.logger.error("Failed to delete localization: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
          render_operation_failed("Failed to delete localization: #{sanitize_error_message(e)}")
        end
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_version
        @version = @organization.app_store_versions.find(params[:app_store_version_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("App Store version")
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

      def versions_service_for(credential)
        apple_client = AppStoreConnect::Client.new(credential: credential)
        AppStoreConnect::Versions.new(apple_client)
      end

      def verify_read_scope
        verify_read_scope!
      end

      def verify_write_scope
        verify_write_scope!
      end

      # Normalize localization params (strip whitespace, convert empty strings to nil)
      def normalize_localizations_params
        [ :description, :keywords, :whats_new, :marketing_url, :promotional_text, :support_url ].each do |key|
          if params[key].present?
            params[key] = params[key].to_s.strip.presence
          else
            params[key] = nil
          end
        end
      end

      def localization_json(loc)
        return nil unless loc
        attrs = loc["attributes"] || {}
        {
          id: loc["id"],
          locale: attrs["locale"],
          description: attrs["description"],
          keywords: attrs["keywords"],
          whats_new: attrs["whatsNew"],
          marketing_url: attrs["marketingUrl"],
          promotional_text: attrs["promotionalText"],
          support_url: attrs["supportUrl"]
        }
      end
    end
  end
end
