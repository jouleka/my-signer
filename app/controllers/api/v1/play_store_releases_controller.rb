module Api
  module V1
    class PlayStoreReleasesController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :set_play_store_release, only: [ :show, :update ]
      before_action :verify_read_scope, only: [ :index, :show ]
      before_action :verify_write_scope, only: [ :create, :update ]

      # GET /api/v1/organizations/:organization_id/play_store_releases
      # Optional params:
      #   - package_name: filter by package name
      def index
        authorize @organization, :show?

        scope = PlayStoreRelease.joins(:android_app)
                                 .where(android_apps: { organization_id: @organization.id })

        if params[:package_name].present?
          app = @organization.android_apps.find_by(package_name: params[:package_name])
          return render_not_found("Android app") unless app
          releases = app.play_store_releases.order(Arel.sql("COALESCE(released_at, created_at) DESC"))
          if releases.empty?
            return render_not_found("Play Store releases", details: { package_name: params[:package_name] })
          end

          return render json: {
            play_store_releases: releases.map { |r| play_store_release_json(r) }
          }
        end

        releases = scope.includes(:android_app).order(Arel.sql("COALESCE(play_store_releases.released_at, play_store_releases.created_at) DESC"))
        render json: {
          play_store_releases: releases.map { |r| play_store_release_json(r) }
        }
      end

      # GET /api/v1/organizations/:organization_id/play_store_releases/:id
      def show
        authorize @organization, :show?
        render json: play_store_release_json(@play_store_release)
      end

      # POST /api/v1/organizations/:organization_id/play_store_releases
      # Body: { play_store_release: { android_app_id:, track:, release_notes:, status_url:, user_fraction:, auto_submit:, localizations: {} } }
      def create
        authorize @organization, :manage_resources?

        app = @organization.android_apps.find_by(id: params.dig(:play_store_release, :android_app_id))
        return render_not_found("Android app") unless app

        release = app.play_store_releases.new(play_store_release_params)

        if release.save
          sync_release_notes_to_store_listing(release, params[:play_store_release])
          render json: play_store_release_json(release), status: :created
        else
          render_validation_failed("Failed to create Play Store release", details: release.errors.full_messages)
        end
      end

      # PATCH /api/v1/organizations/:organization_id/play_store_releases/:id
      def update
        authorize @organization, :manage_resources?

        if @play_store_release.update(play_store_release_params)
          sync_release_notes_to_store_listing(@play_store_release, params[:play_store_release])
          render json: play_store_release_json(@play_store_release)
        else
          render_validation_failed("Failed to update Play Store release", details: @play_store_release.errors.full_messages)
        end
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_play_store_release
        @play_store_release = PlayStoreRelease.joins(:android_app)
                                             .where(android_apps: { organization_id: @organization.id })
                                             .find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Play Store release")
      end

      def verify_read_scope
        verify_read_scope!
      end

      def verify_write_scope
        verify_write_scope!
      end

      def play_store_release_params
        permitted = params.require(:play_store_release).permit(
          :track,
          :release_notes,
          :status_url,
          :user_fraction,
          :auto_submit,
          :version_code,
          :status,
          :released_at
        )

        # localizations is a JSONB column — Rails strong params silently strips
        # array/hash values when declared as a scalar key. Extract manually,
        # supporting both hash format ({ "en-US" => {...} }) and array format
        # ([{ locale: "en-US", ... }]) that different clients may send.
        raw_localizations = params.dig(:play_store_release, :localizations)
        if raw_localizations.present?
          permitted[:localizations] = if raw_localizations.is_a?(Array)
            raw_localizations.map { |item| item.respond_to?(:to_unsafe_h) ? item.to_unsafe_h : item.to_h }
          else
            raw_localizations.respond_to?(:to_unsafe_h) ? raw_localizations.to_unsafe_h : raw_localizations.to_h
          end
        end

        permitted
      end

      def play_store_release_json(release)
        primary = release.android_app&.primary_locale
        store_listing_whats_new = release.android_app
                                         &.store_listings
                                         &.find_by(locale: primary)
                                         &.whats_new
        {
          id: release.id,
          android_app_id: release.android_app_id,
          package_name: release.android_app&.package_name,
          track: release.track,
          release_notes: store_listing_whats_new.presence || release.release_notes,
          status_url: release.status_url,
          user_fraction: release.user_fraction,
          auto_submit: release.auto_submit,
          status: release.status,
          version_code: release.version_code,
          released_at: release.released_at&.iso8601,
          localizations: release.localizations,
          created_at: release.created_at.iso8601,
          updated_at: release.updated_at.iso8601
        }
      end

      def sync_release_notes_to_store_listing(release, content_params)
        return unless content_params
        notes = content_params[:release_notes]
        return if notes.blank?

        android_app = release.android_app
        return unless android_app

        listing = android_app.store_listings.find_or_initialize_by(locale: android_app.primary_locale)
        listing.organization = android_app.organization if listing.new_record?
        listing.sync_status ||= "draft"
        listing.whats_new = notes
        listing.save
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("Failed to sync release notes to StoreListing: #{e.message}")
      end
    end
  end
end
