class AndroidTracksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org

  def index
    authorize @organization, :show?

    @q_track = params[:track].presence
    @q_app = params[:app].presence

    # Stats
    @total_tracks = AndroidTrack.joins(:android_app).where(android_apps: { organization_id: @organization.id }).count
    @apps_with_tracks = @organization.android_apps.joins(:android_tracks).distinct.count

    # Table data with eager loading
    scope = AndroidTrack.joins(:android_app).where(android_apps: { organization_id: @organization.id }).includes(:android_app)
    scope = scope.where(track_name: @q_track) if @q_track.present?
    if @q_app.present?
      scope = scope.where(android_app_id: @q_app)
    end

    @tracks = scope.order("android_apps.name ASC, android_tracks.track_name ASC").limit(500)

    # Filter options
    @track_names = AndroidTrack::TRACKS
    @apps = @organization.android_apps.order(:name)
  end

  private

  def set_org
    # Scoped to caller's orgs so non-member access 404s like a missing id —
    # closes the org-id enumeration oracle. See
    # OrganizationsController#set_organization for full rationale.
    @organization = current_user.organizations.find(params[:organization_id])
  end
end
