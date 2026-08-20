class SigningAssetsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org

  def show
    authorize @organization, :show?
    set_current_organization!(@organization)

    # iOS counts
    @certificates_count = @organization.apple_certificates.count
    @devices_count = @organization.apple_devices.count
    @profiles_count = @organization.apple_provisioning_profiles.count
    @bundle_ids_count = @organization.apple_bundle_ids.count
    @apple_apps_count = @organization.apple_apps.count
    @beta_groups_count = @organization.testflight_beta_groups.count

    # Android counts
    @android_apps_count = @organization.android_apps.count
    @keystores_count = @organization.android_keystores.count
    @tracks_count = AndroidTrack.joins(:android_app).where(android_apps: { organization_id: @organization.id }).count
  end

  private

  def set_org
    # Scoped to caller's orgs so non-member access 404s like a missing id —
    # closes the org-id enumeration oracle. See
    # OrganizationsController#set_organization for full rationale.
    @organization = current_user.organizations.find(params[:organization_id])
  end
end
