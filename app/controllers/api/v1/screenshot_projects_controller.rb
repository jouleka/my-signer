module Api
  module V1
    class ScreenshotProjectsController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :set_project, only: [ :show ]
      before_action :verify_read_scope, only: [ :index, :show ]

      # GET /api/v1/organizations/:organization_id/screenshot_projects
      def index
        authorize @organization, :show?

        projects = @organization.screenshot_projects.order(updated_at: :desc)

        render json: {
          data: {
            projects: projects.map { |p| project_json(p) }
          }
        }
      end

      # GET /api/v1/organizations/:organization_id/screenshot_projects/:id
      def show
        authorize @organization, :show?

        render json: {
          data: project_json(@project).merge(
            scenes: @project.screenshot_scenes.map { |s| scene_json(s) }
          )
        }
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_project
        @project = @organization.screenshot_projects.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Screenshot project")
      end

      def verify_read_scope
        verify_read_scope!
      end

      def project_json(project)
        {
          id: project.id,
          name: project.name,
          platform: project.platform,
          scenes_count: project.scenes_count,
          has_exports: project.exports_directory.exist? && project.exports_directory.children.any?,
          plan_access_state: project.plan_access_state,
          plan_frozen: project.plan_frozen_on_current_plan?,
          plan_frozen_reason: project.plan_frozen_reason,
          created_at: project.created_at.iso8601,
          updated_at: project.updated_at.iso8601
        }
      rescue Errno::ENOENT
        {
          id: project.id,
          name: project.name,
          platform: project.platform,
          scenes_count: project.scenes_count,
          has_exports: false,
          plan_access_state: project.plan_access_state,
          plan_frozen: project.plan_frozen_on_current_plan?,
          plan_frozen_reason: project.plan_frozen_reason,
          created_at: project.created_at.iso8601,
          updated_at: project.updated_at.iso8601
        }
      end

      def scene_json(scene)
        {
          id: scene.id,
          position: scene.position,
          caption_text: scene.caption_text,
          subtitle_text: scene.subtitle_text,
          source_image_width: scene.source_image_width,
          source_image_height: scene.source_image_height
        }
      end
    end
  end
end
