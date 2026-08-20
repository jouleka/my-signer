class ApiTokenPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      return scope.none unless user
      # Users can see tokens from orgs they belong to
      scope.where(organization_id: OrganizationPolicy::Scope.new(user, Organization).resolve.select(:id))
    end
  end

  def index?
    developer_or_higher?
  end

  def create?
    developer_or_higher?
  end

  def destroy?
    # Users can revoke their own tokens, or admins can revoke any token
    return true if record.user_id == user.id && developer_or_higher?
    admin_or_owner?
  end

  # Check if user can create token with specific scope
  def can_use_scope?(scope)
    return false unless create?

    # Admin scope requires admin or owner role
    return admin_or_owner? if scope.to_s == "admin"

    # Read and write scopes available to developers and higher
    true
  end

  private

  def org
    record.organization
  end

  def admin_or_owner?
    return false unless org.accessible?

    org.owner_id == user.id || org.memberships.where(user_id: user.id, role: :admin).exists?
  end

  def developer_or_higher?
    return false unless org.accessible?
    return false unless org.memberships.exists?(user_id: user.id)
    membership = org.memberships.find_by(user_id: user.id)
    org.owner_id == user.id || membership&.role.in?([ "admin", "developer" ])
  end
end
