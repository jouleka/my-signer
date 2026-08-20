module Api
  module V1
    class BuildsController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :verify_read_scope

      # GET /api/v1/organizations/:organization_id/builds
      # Params: app_id, version, build_number, processed_only
      def index
        authorize @organization, :show?

        scope = @organization.apple_builds

        if params[:app_id].present?
          scope = scope.where(apple_app_id: params[:app_id])
        end

        if params[:version].present? && params[:build_number].present?
          # Exact match: specific version and build number
          scope = scope.by_version_and_build(params[:version], params[:build_number])
        elsif params[:version].present?
          # Only version specified: get all builds for that version, sorted by build number
          scope = scope.where(version: params[:version])
        end

        # Filter by minimum build number
        if params[:min_build_number].present?
          scope = scope.where("CAST(build_number AS INTEGER) >= ?", params[:min_build_number].to_i)
        end

        # Filter for processed builds only (VALID or PROCESSING_COMPLETE)
        if params[:processed_only].present? && params[:processed_only] != "false"
          scope = scope.processed
        end

        # Pagination
        page = [ params[:page].to_i, 1 ].max
        per_page = [ [ params[:per_page].to_i, 1 ].max, 100 ].min
        per_page = 50 if per_page == 1 && params[:per_page].blank?

        total = scope.count
        # Order by uploaded_date desc to get latest first
        builds = scope.order(uploaded_date: :desc).offset((page - 1) * per_page).limit(per_page)

        render json: {
          data: {
            builds: builds.map { |b| build_json(b) }
          },
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            total_pages: (total.to_f / per_page).ceil
          }
        }
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def verify_read_scope
        verify_read_scope!
      end

      def build_json(build)
        {
          id: build.id,
          build_id: build.build_id,
          version: build.version,
          build_number: build.build_number,
          processing_state: build.processing_state,
          uploaded_date: build.uploaded_date&.iso8601,
          expires_at: build.expires_at&.iso8601,
          created_at: build.created_at.iso8601,
          updated_at: build.updated_at.iso8601
        }
      end
    end
  end
end
