module Api
  module V1
    class BundleIdsController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :set_bundle_id, only: [ :show, :destroy ]
      before_action :verify_read_scope, only: [ :index, :show ]
      before_action :verify_write_or_admin_scope, only: [ :create, :destroy ]

      # GET /api/v1/organizations/:organization_id/bundle_ids
      # Returns all bundle IDs for the organization with optional filters
      def index
        authorize @organization, :show?

        scope = @organization.apple_bundle_ids

        # Apply filters
        scope = scope.where(platform: params[:platform]) if params[:platform].present?

        # Apply search query
        if params[:q].present?
          query = params[:q].strip
          scope = scope.where("identifier ILIKE :q OR name ILIKE :q", q: "%#{query}%")
        end

        # Pagination
        page = [ params[:page].to_i, 1 ].max
        per_page = [ [ params[:per_page].to_i, 1 ].max, 100 ].min
        per_page = 50 if per_page == 1 && params[:per_page].blank?

        total = scope.count
        bundle_ids = scope.order(identifier: :asc).offset((page - 1) * per_page).limit(per_page)

        render json: {
          bundle_ids: bundle_ids.map { |bundle_id| bundle_id_json(bundle_id) },
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            total_pages: (total.to_f / per_page).ceil
          }
        }
      end

      # GET /api/v1/organizations/:organization_id/bundle_ids/:id
      # Returns detailed information about a specific bundle ID
      def show
        authorize @organization, :show?

        render json: bundle_id_json(@bundle_id)
      end

      # POST /api/v1/organizations/:organization_id/bundle_ids
      # Register a new Bundle ID with App Store Connect
      def create
        authorize @organization, :sync?

        # Validate required params
        unless params[:identifier].present?
          return render_invalid_request("Missing required parameter: identifier")
        end

        # Get active App Store Connect credential
        credential = @organization.app_store_connect_credentials.where(active: true).first
        unless credential
          return render_credentials_required("No active App Store Connect credential found")
        end

        # Check if bundle ID already exists
        existing_bundle_id = @organization.apple_bundle_ids.find_by(identifier: params[:identifier])
        if existing_bundle_id
          return render_conflict(
            "Bundle ID #{params[:identifier]} already exists",
            resource_id: existing_bundle_id.id,
            details: { bundle_id: bundle_id_json(existing_bundle_id) }
          )
        end

        # Default name to last part of identifier if not provided
        name = params[:name].presence || params[:identifier].split(".").last.capitalize
        platform = params[:platform].presence || "IOS"

        # Register bundle ID with App Store Connect
        begin
          client = AppStoreConnect::Client.new(credential: credential)
          service = AppStoreConnect::BundleIds.new(client)
          response = service.register(
            identifier: params[:identifier],
            name: name,
            platform: platform
          )

          # Create bundle ID record
          attributes = response.dig("data", "attributes") || {}
          bundle_id = @organization.apple_bundle_ids.create!(
            remote_id: response.dig("data", "id"),
            identifier: attributes["identifier"] || params[:identifier],
            name: attributes["name"] || name,
            platform: attributes["platform"] || platform,
            team_id: credential.team_id,
            raw_json: JSON.dump(response)
          )

          render json: {
            message: "Bundle ID registered successfully",
            bundle_id: bundle_id_json(bundle_id)
          }, status: :created
        rescue => e
          Rails.logger.error("Bundle ID registration failed: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
          render_operation_failed("Bundle ID registration failed: #{sanitize_error_message(e)}")
        end
      end

      # DELETE /api/v1/organizations/:organization_id/bundle_ids/:id
      # Remove a Bundle ID from both App Store Connect and local tracking.
      # If the Bundle ID has dependent apps, profiles, or capabilities Apple
      # returns 409 — we surface that as an actionable error instead of
      # silently destroying the local record.
      def destroy
        authorize @organization, :sync?

        credential = @organization.app_store_connect_credentials.where(active: true).first
        unless credential
          return render_credentials_required("No active App Store Connect credential found")
        end

        remote_id = @bundle_id.remote_id
        identifier = @bundle_id.identifier

        begin
          client = AppStoreConnect::Client.new(credential: credential)
          service = AppStoreConnect::BundleIds.new(client)
          service.delete(remote_id) if remote_id.present?
        rescue => e
          # Apple's 409 messages mention the related resource ("apps",
          # "profiles", "bundleIdCapabilities"). Surface that so the caller
          # can fix it instead of seeing a generic failure.
          if e.message =~ /(409|conflict|has (?:related|dependent)|related resource|apps|profile|capabilit)/i
            Audit::Logger.log(
              organization: @organization,
              actor: current_user,
              action: "bundle_id_delete_refused",
              metadata: { bundle_id_id: @bundle_id.id, identifier: identifier, reason: e.message },
              request: request
            )
            return render json: {
              error: "Apple refused to delete Bundle ID #{identifier}. Remove dependent resources first (apps, profiles, or capabilities) in App Store Connect.",
              details: { message: sanitize_error_message(e) }
            }, status: :conflict
          end

          Rails.logger.error("Bundle ID deletion failed: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
          return render_operation_failed("Bundle ID deletion failed: #{sanitize_error_message(e)}")
        end

        @bundle_id.destroy!

        Audit::Logger.log(
          organization: @organization,
          actor: current_user,
          action: "bundle_id_deleted",
          metadata: { bundle_id_id: @bundle_id.id, identifier: identifier, remote_id: remote_id },
          request: request
        )

        render json: { message: "Bundle ID #{identifier} deleted from App Store Connect and local cache" }
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_bundle_id
        @bundle_id = @organization.apple_bundle_ids.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Bundle ID")
      end

      def verify_read_scope
        verify_read_scope!
      end

      def verify_write_or_admin_scope
        verify_write_scope!
      end

      def bundle_id_json(bundle_id)
        {
          id: bundle_id.id,
          remote_id: bundle_id.remote_id,
          identifier: bundle_id.identifier,
          name: bundle_id.name,
          platform: bundle_id.platform,
          created_at: bundle_id.created_at.iso8601,
          updated_at: bundle_id.updated_at.iso8601
        }
      end
    end
  end
end
