class AndroidAppsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org
  before_action :set_app, only: [ :show, :releases ]

  def index
    authorize @organization, :show?

    @q_query = params[:q].to_s.strip.presence

    # Stats
    @total_apps = @organization.android_apps.count
    @total_builds = @organization.android_builds.count

    # Table data
    scope = @organization.android_apps.includes(:android_builds, :android_tracks, :play_store_release)
    if @q_query
      scope = scope.where("package_name ILIKE :q OR name ILIKE :q", q: "%#{@q_query}%")
    end

    @apps = scope.order(name: :asc, package_name: :asc).limit(500)
  end

  def show
    authorize @organization, :show?

    @builds = @app.android_builds.recent.limit(50)
    @tracks = @app.android_tracks.order(:track_name)
    @keystores = @organization.android_keystores.where(android_app_id: [ @app.id, nil ]).order(active: :desc, created_at: :desc)
    @releases = @app.play_store_releases.recent.limit(20)
  end

  def releases
    authorize @organization, :show?

    @track_filter = params[:track].presence
    @status_filter = params[:status].presence

    scope = @app.play_store_releases.recent
    scope = scope.where(track: @track_filter) if @track_filter
    scope = scope.with_status(@status_filter) if @status_filter

    @releases = scope.limit(100)
  end

  def new
    authorize @organization, :manage_resources?
    @app = @organization.android_apps.build
  end

  def create
    authorize @organization, :manage_resources?
    @app = @organization.android_apps.build(app_params)

    if @app.save
      redirect_to organization_android_app_path(@organization, @app),
                  notice: "App added! Run a sync to fetch metadata from Google Play."
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def app_params
    params.require(:android_app).permit(:package_name, :name)
  end

  def set_org
    # Scoped to caller's orgs so non-member access 404s like a missing id —
    # closes the org-id enumeration oracle. See
    # OrganizationsController#set_organization for full rationale.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def set_app
    @app = @organization.android_apps.find(params[:id])
  end
end
