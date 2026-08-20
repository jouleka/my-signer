module Api
  module V1
    class AppGroupsController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :set_app_group, only: [ :show, :destroy ]
      before_action :verify_read_scope, only: [ :index, :show ]
      before_action :verify_write_or_admin_scope, only: [ :create, :destroy ]

      # GET /api/v1/organizations/:organization_id/app_groups
      # Returns all app groups for the organization
      def index
        authorize @organization, :show?

        scope = @organization.apple_app_groups

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
        app_groups = scope.sorted.offset((page - 1) * per_page).limit(per_page)

        render json: {
          app_groups: app_groups.map { |g| app_group_json(g) },
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            total_pages: (total.to_f / per_page).ceil
          }
        }
      end

      # GET /api/v1/organizations/:organization_id/app_groups/:id
      # Returns detailed information about a specific app group
      def show
        authorize @organization, :show?

        render json: app_group_json(@app_group, include_bundle_ids: true)
      end

      # POST /api/v1/organizations/:organization_id/app_groups
      # Register an app group (local only - must be created in Apple Portal first)
      def create
        authorize @organization, :sync?

        unless params[:identifier].present?
          return render_invalid_request("Missing required parameter: identifier")
        end

        unless params[:identifier].start_with?("group.")
          return render_invalid_request("Identifier must start with 'group.'")
        end

        # Check if app group already exists
        existing = @organization.apple_app_groups.find_by(identifier: params[:identifier])
        if existing
          return render_conflict(
            "App Group with identifier #{params[:identifier]} already exists",
            resource_id: existing.id,
            details: { app_group: app_group_json(existing) }
          )
        end

        credential = @organization.app_store_connect_credentials.where(active: true).first
        team_id = credential&.team_id

        begin
          # Note: Apple does NOT have a public API for creating App Groups.
          # This only registers the App Group locally in My Signer.
          app_group = @organization.apple_app_groups.create!(
            identifier: params[:identifier],
            name: params[:name].presence || params[:identifier],
            team_id: team_id
          )

          render json: {
            message: "App Group registered locally. Remember to also create it in the Apple Developer Portal.",
            app_group: app_group_json(app_group)
          }, status: :created
        rescue ActiveRecord::RecordInvalid => e
          render_validation_failed(e.record.errors.full_messages.join(", "))
        rescue => e
          Rails.logger.error("App Group creation failed: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
          render_operation_failed("App Group creation failed: #{sanitize_error_message(e)}")
        end
      end

      # DELETE /api/v1/organizations/:organization_id/app_groups/:id
      # Remove an app group from My Signer (does not delete from Apple)
      def destroy
        authorize @organization, :sync?

        @app_group.destroy!

        render json: {
          message: "App Group removed from My Signer. The App Group in Apple Developer Portal must be deleted manually."
        }
      rescue => e
        Rails.logger.error("App Group deletion failed: #{e.class} - #{e.message}")
        Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
        render_operation_failed("App Group deletion failed: #{sanitize_error_message(e)}")
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_app_group
        @app_group = @organization.apple_app_groups.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("App Group")
      end

      def verify_read_scope
        verify_read_scope!
      end

      def verify_write_or_admin_scope
        verify_write_scope!
      end

      def app_group_json(app_group, include_bundle_ids: false)
        json = {
          id: app_group.id,
          identifier: app_group.identifier,
          name: app_group.name,
          team_id: app_group.team_id,
          created_at: app_group.created_at.iso8601,
          updated_at: app_group.updated_at.iso8601
        }

        if include_bundle_ids
          json[:bundle_ids] = app_group.apple_bundle_ids.map do |b|
            {
              id: b.id,
              identifier: b.identifier,
              name: b.name
            }
          end
        end

        json
      end
    end
  end
end
