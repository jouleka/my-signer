class AppleAppsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org
  before_action :set_app, only: [ :show, :releases ]

  def index
    authorize @organization, :show?

    @q_query = params[:q].to_s.strip.presence

    # Stats
    @total_apps = @organization.apple_apps.count
    @total_builds = @organization.apple_builds.count
    @total_beta_groups = @organization.testflight_beta_groups.count

    # Table data
    scope = @organization.apple_apps.includes(:apple_builds, :testflight_beta_groups, :app_store_versions)
    if @q_query
      scope = scope.where("bundle_id ILIKE :q OR name ILIKE :q", q: "%#{@q_query}%")
    end

    @apps = scope.order(name: :asc, bundle_id: :asc).limit(500)
  end

  def show
    authorize @organization, :show?

    @builds = @app.apple_builds.order(uploaded_date: :desc).limit(50)
    @beta_groups = @app.testflight_beta_groups.order(is_internal_group: :desc, name: :asc)
    @versions = @app.app_store_versions.includes(:apple_build).order(created_at: :desc).limit(20)

    # CLI defaults for this app (formerly AppStoreRelease; now apple_apps.cli_defaults)
    @bundle_id_record = @organization.apple_bundle_ids.find_by(identifier: @app.bundle_id)
    @store_listing = @app.store_listings.find_by(locale: @app.primary_locale) ||
                     @app.store_listings.first
  end

  def releases
    authorize @organization, :show?

    @state_filter = params[:state].presence

    scope = @app.app_store_versions.includes(:apple_build).order(created_at: :desc)
    scope = scope.where(app_store_state: @state_filter) if @state_filter

    @versions = scope.limit(100)
  end

  private

  def set_org
    # Scoped to caller's orgs so non-member access 404s like a missing id —
    # closes the org-id enumeration oracle. See
    # OrganizationsController#set_organization for full rationale.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def set_app
    @app = @organization.apple_apps.find(params[:id])
  end
end
