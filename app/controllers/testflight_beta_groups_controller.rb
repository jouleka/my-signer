class TestflightBetaGroupsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org

  def index
    authorize @organization, :show?

    @beta_groups = @organization.testflight_beta_groups
      .includes(:apple_app)
      .order(is_internal_group: :desc, name: :asc)
  end

  private

  def set_org
    # Scoped to caller's orgs so non-member access 404s like a missing id —
    # closes the org-id enumeration oracle. See
    # OrganizationsController#set_organization for full rationale.
    @organization = current_user.organizations.find(params[:organization_id])
  end
end
