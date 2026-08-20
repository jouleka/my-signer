class AuditEventPolicy < ApplicationPolicy
  # Audit log viewing is restricted to admins/owners of an organization on
  # the Team tier. The `record` passed to this policy is the Organization
  # (because index/export authorize the org, not individual events) -- the
  # scope class below handles the event-level scoping for queries.
  class Scope < Scope
    # Narrow AuditEvent queries to organizations where the current user is
    # an owner or admin member AND the org is on a tier with audit log
    # visibility enabled. This defends against future callers of
    # `policy_scope(AuditEvent)` leaking audit data from Free/Pro orgs or
    # from orgs where the user is only a viewer/developer. The controller
    # currently calls `authorize @organization, :index?` which is sufficient,
    # but this scope enforcement is belt-and-suspenders for any future
    # admin/rollup view.
    def resolve
      return scope.none unless user

      eligible_org_ids = Organization
        .accessible
        .joins(:memberships)
        .joins(:owner)
        .where(memberships: { user_id: user.id })
        .where("organizations.owner_id = :uid OR memberships.role = :admin_role",
               uid: user.id,
               admin_role: Membership.roles[:admin])
        .where(owner: { plan_tier: User.plan_tiers[:team] })
        .distinct
        .select(:id)

      scope.where(organization_id: eligible_org_ids)
    end
  end

  def index?
    admin_or_owner? && team_tier?
  end

  def export?
    index?
  end

  private

  def organization
    record  # policy is called with Organization instance
  end

  def admin_or_owner?
    return false unless user
    return false unless organization.respond_to?(:owner_id)
    return false unless organization.accessible?
    organization.owner_id == user.id ||
      organization.memberships.where(user_id: user.id, role: :admin).exists?
  end

  def team_tier?
    organization.entitlements.audit_log_enabled?
  end
end
