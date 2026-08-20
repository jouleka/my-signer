module Api
  module V1
    class AndroidAppsController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :set_android_app, only: [ :show ]
      before_action :verify_read_scope, only: [ :index, :show ]
      before_action :verify_write_scope, only: [ :create ]

      # GET /api/v1/organizations/:organization_id/android_apps
      # Optional params: q (search by package_name or name)
      def index
        authorize @organization, :show?

        scope = @organization.android_apps
        if params[:q].present?
          q = params[:q].to_s.strip
          scope = scope.where("package_name ILIKE :q OR name ILIKE :q", q: "%#{q}%")
        end

        # Pagination
        page = [ params[:page].to_i, 1 ].max
        per_page = [ [ params[:per_page].to_i, 1 ].max, 100 ].min
        per_page = 50 if per_page == 1 && params[:per_page].blank?

        total = scope.count
        apps = scope.order(package_name: :asc).offset((page - 1) * per_page).limit(per_page)

        render json: {
          android_apps: apps.map { |a| android_app_json(a) },
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            total_pages: (total.to_f / per_page).ceil
          }
        }
      end

      # GET /api/v1/organizations/:organization_id/android_apps/:id
      # Note: id is the record id (not package name) to stay consistent with other endpoints.
      def show
        authorize @organization, :show?
        render json: android_app_json(@android_app)
      end

      # GET /api/v1/organizations/:organization_id/android_apps/package/:package_name
      def show_by_package
        authorize @organization, :show?
        pkg = params[:package_name].to_s.strip
        # Tolerate accidental format suffix on the glob segment
        pkg = pkg.sub(/\.(json|html)\z/i, "")
        app = @organization.android_apps.find_by(package_name: pkg)
        if app
          render json: android_app_json(app)
        else
          render_not_found("Android app")
        end
      end

      # POST /api/v1/organizations/:organization_id/android_apps
      # Body: { android_app: { package_name:, name: (optional) } }
      def create
        authorize @organization, :manage_resources?

        app = @organization.android_apps.build(app_params)

        if app.save
          render json: { android_app: android_app_json(app) }, status: :created
        else
          render_validation_failed("Failed to create Android app", details: app.errors.full_messages)
        end
      end

      private

      def app_params
        params.require(:android_app).permit(:package_name, :name)
      end

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_android_app
        @android_app = @organization.android_apps.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Android app")
      end

      def verify_read_scope
        verify_read_scope!
      end

      def verify_write_scope
        verify_write_scope!
      end

      def android_app_json(app)
        {
          id: app.id,
          package_name: app.package_name,
          name: app.name,
          default_language: app.default_language,
          builds_count: app.android_builds.count,
          highest_version_code: app.android_builds.maximum(:version_code)&.to_i || 0,
          created_at: app.created_at.iso8601,
          updated_at: app.updated_at.iso8601
        }
      end
    end
  end
end
