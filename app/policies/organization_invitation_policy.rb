class OrganizationInvitationPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      return scope.none unless user
      scope.where(organization_id: OrganizationPolicy::Scope.new(user, Organization).resolve.select(:id))
    end
  end

  def create?
    # Developers can invite, but role restriction is in can_invite_role?
    developer_or_higher?
  end

  def destroy?
    admin_or_owner?
  end

  # Check if user can invite someone with a specific role
  def can_invite_role?(role)
    return false unless create?

    # Admins and owners can invite anyone
    return true if admin_or_owner?

    # Developers can only invite developers and viewers
    role.to_s.in?([ "developer", "viewer" ])
  end

  def accept?
    # Invitation tokens are bearer secrets. The actual membership mutation guard
    # lives in OrganizationInvitation#accept!, which only allows the invited email
    # to consume the invite and lets the UI surface a precise mismatch error.
    true
  end

  private

  def admin_or_owner?
    org = record.organization
    return false unless org.accessible?

    org.owner_id == user.id || org.memberships.where(user_id: user.id, role: :admin).exists?
  end

  def developer_or_higher?
    org = record.organization
    return false unless org.accessible?
    return false unless org.memberships.exists?(user_id: user.id)
    membership = org.memberships.find_by(user_id: user.id)
    org.owner_id == user.id || membership&.role.in?([ "admin", "developer" ])
  end
end
