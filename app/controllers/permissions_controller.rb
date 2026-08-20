class PermissionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org
  # Render Team-feature paywall BEFORE Pundit so non-Team users see an
  # upgrade page rather than the generic Pundit denial.
  before_action :require_rbac_entitlement!
  after_action :verify_authorized

  # Shows the organization's role-permission matrix. Team-only feature;
  # any org member can view the matrix on Team plans.
  def index
    authorize @organization, :show?, policy_class: OrganizationPolicy

    @entitlements = @organization.entitlements
    @memberships = @organization.memberships.includes(:user).order("users.email ASC")
  end

  private

  def set_org
    # Scope to memberships so non-member access returns 404 before the
    # feature-gate renders the paywall page (which echoes org name + plan
    # tier into the DOM — a cross-org enumeration oracle otherwise).
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def require_rbac_entitlement!
    return if @organization.entitlements.rbac_enabled?

    render_team_feature_paywall!(
      name: "Permissions Matrix",
      icon: "fa-key",
      description: "See exactly what each role on your team can do, and manage role-based access at a glance.",
      bullets: [
        "Per-role capability matrix (Viewer, Developer, Admin, Owner)",
        "Full team roster with role badges",
        "Audit who can manage credentials, billing, and members",
        "Foundation for fine-grained permissions"
      ]
    )
  end
end
