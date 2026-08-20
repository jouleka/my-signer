module Api
  module V1
    class AppleAppsController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :set_apple_app, only: [ :show ]
      before_action :verify_read_scope, only: [ :index, :show ]

      # GET /api/v1/organizations/:organization_id/apple_apps
      # Optional params:
      #   q (search by bundle_id or name)
      #   bundle_id (filter by exact bundle_id)
      def index
        authorize @organization, :show?

        scope = @organization.apple_apps

        if params[:bundle_id].present?
          scope = scope.where(bundle_id: params[:bundle_id])
        elsif params[:q].present?
          q = params[:q].to_s.strip
          scope = scope.where("bundle_id ILIKE :q OR name ILIKE :q", q: "%#{q}%")
        end

        # Pagination
        page = [ params[:page].to_i, 1 ].max
        per_page = [ [ params[:per_page].to_i, 1 ].max, 100 ].min
        per_page = 50 if per_page == 1 && params[:per_page].blank?

        total = scope.count
        apps = scope.order(name: :asc).offset((page - 1) * per_page).limit(per_page)

        render json: {
          data: {
            apps: apps.map { |a| apple_app_json(a) }
          },
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            total_pages: (total.to_f / per_page).ceil
          }
        }
      end

      # GET /api/v1/organizations/:organization_id/apple_apps/:id
      def show
        authorize @organization, :show?
        render json: apple_app_json(@apple_app)
      end

      # GET /api/v1/organizations/:organization_id/apple_apps/bundle_id/:bundle_id
      def show_by_bundle_id
        authorize @organization, :show?
        bundle_id = params[:bundle_id].to_s.strip
        app = @organization.apple_apps.find_by(bundle_id: bundle_id)
        if app
          render json: apple_app_json(app)
        else
          render_not_found("Apple app")
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
        render_not_found("Apple app")
      end

      def verify_read_scope
        verify_read_scope!
      end

      def apple_app_json(app)
        {
          id: app.id,
          app_store_id: app.app_store_id,
          bundle_id: app.bundle_id,
          name: app.name,
          sku: app.sku,
          created_at: app.created_at.iso8601,
          updated_at: app.updated_at.iso8601
        }
      end
    end
  end
end
