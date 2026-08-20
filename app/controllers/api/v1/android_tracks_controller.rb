module Api
  module V1
    class AndroidTracksController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :set_android_app_by_package!
      before_action :verify_read_scope

      # GET /api/v1/organizations/:organization_id/android_apps/package/:package_name/tracks
      def index
        authorize @organization, :show?

        tracks = @android_app.android_tracks.order(track_name: :asc)
        render json: {
          package_name: @android_app.package_name,
          tracks: tracks.map { |t| track_json(t) }
        }
      end

      # GET /api/v1/organizations/:organization_id/android_apps/package/:package_name/tracks/:track
      def show
        authorize @organization, :show?

        track = @android_app.android_tracks.find_by(track_name: params[:track])
        if track
          render json: track_json(track)
        else
          render_not_found("Track")
        end
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_android_app_by_package!
        pkg = params[:package_name].to_s.strip
        @android_app = @organization.android_apps.find_by(package_name: pkg)
      rescue
        @android_app = nil
      ensure
        unless @android_app
          render_not_found("Android app")
        end
      end

      def verify_read_scope
        verify_read_scope!
      end

      def track_json(t)
        {
          id: t.id,
          track_name: t.track_name,
          status: t.status,
          releases: t.releases,
          updated_at: t.updated_at.iso8601
        }
      end
    end
  end
end
