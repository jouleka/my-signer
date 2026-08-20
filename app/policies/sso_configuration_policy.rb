class SsoConfigurationPolicy < ApplicationPolicy
  # SSO configuration is admin-only and Team-tier only. Non-admins see no
  # SSO settings page. Free/Pro tier orgs see a paywall (handled in the
  # controller, which wraps the policy check with a specific redirect).

  def show?;    admin_or_owner?; end
  def new?;     admin_or_owner? && sso_entitlement?; end
  def create?;  admin_or_owner? && sso_entitlement?; end
  def edit?;    admin_or_owner? && sso_entitlement?; end
  def update?;  admin_or_owner? && sso_entitlement?; end
  def destroy?; admin_or_owner?; end

  private

  def organization
    # record is either an SsoConfiguration instance or an Organization.
    # Normalize to the organization either way.
    record.respond_to?(:organization) ? record.organization : record
  end

  def admin_or_owner?
    return false unless user
    return false unless organization.respond_to?(:accessible?)
    return false unless organization.accessible?
    organization.owner_id == user.id ||
      organization.memberships.where(user_id: user.id, role: :admin).exists?
  end

  def sso_entitlement?
    organization.entitlements.sso_enabled?
  end
end
