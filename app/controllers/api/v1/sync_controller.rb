module Api
  module V1
    class SyncController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :verify_write_scope

      # POST /api/v1/organizations/:organization_id/sync
      def create
        authorize @organization, :manage_resources?

        unless @organization.app_store_connect_credentials.find_by(active: true)
          return render_credentials_required(
            "No active App Store Connect credential found",
            suggestion: "Please add one in Settings"
          )
        end

        force = ActiveModel::Type::Boolean.new.cast(params[:force])
        result = enqueue_app_store_connect_sync(@organization, force: force, min_interval: AutoSync::SYNC_MANUAL_MIN_INTERVAL)

        case result
        when :enqueued
          render json: {
            message: "Sync enqueued successfully",
            enqueued: true,
            timestamp: Time.current.iso8601
          }, status: :accepted
        when :running
          render json: { message: "Sync already running", enqueued: false }, status: :accepted
        when :fresh
          render json: { message: "Already synced recently. Use --force to sync anyway.", enqueued: false }, status: :ok
        when :cooldown
          render json: { message: "Sync was just queued. Please wait before retrying.", enqueued: false }, status: :too_many_requests
        else
          render_credentials_required("No active App Store Connect credential found", suggestion: "Please add one in Settings")
        end
      end

      private

      def set_organization
        # Handle both :id (member route) and :organization_id (nested route)
        org_id = params[:organization_id] || params[:id]
        @organization = Organization.find(org_id)
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def verify_write_scope
        verify_write_scope!
      end
    end
  end
end
