module Api
  module V1
    class AndroidBuildsController < ApplicationController
      before_action :set_organization
      before_action :set_android_app
      before_action :verify_token_organization_access!
      before_action :verify_write_scope, only: [ :create ]

      # POST /api/v1/organizations/:organization_id/android_apps/:android_app_id/android_builds
      # Body: { android_build: { version_code:, version_name:, status:, track: } }
      def create
        authorize @organization, :manage_resources?

        build = @android_app.android_builds.build(build_params)
        build.organization = @organization

        if build.save
          render json: android_build_json(build), status: :created
        else
          render_validation_failed("Failed to create Android build", details: build.errors.full_messages)
        end
      end

      private

      def build_params
        params.require(:android_build).permit(:version_code, :version_name, :status)
      end

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_android_app
        @android_app = @organization.android_apps.find(params[:android_app_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Android app")
      end

      def verify_write_scope
        verify_write_scope!
      end

      def android_build_json(build)
        {
          id: build.id,
          android_app_id: build.android_app_id,
          version_code: build.version_code.to_i,
          version_name: build.version_name,
          status: build.status,
          created_at: build.created_at.iso8601
        }
      end
    end
  end
end
