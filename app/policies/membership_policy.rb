class MembershipPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      return scope.none unless user
      scope.where(organization_id: OrganizationPolicy::Scope.new(user, Organization).resolve.select(:id))
    end
  end

  def create?
    admin_or_owner?
  end

  def update?
    admin_or_owner? && not_owner_membership?
  end

  def destroy?
    admin_or_owner? && not_owner_membership? && keep_at_least_one_admin?
  end

  private

  def org
    record.organization
  end

  def admin_or_owner?
    return false unless org.accessible?

    org.owner_id == user.id || org.memberships.where(user_id: user.id, role: :admin).exists?
  end

  def not_owner_membership?
    !(record.user_id == org.owner_id)
  end

  def keep_at_least_one_admin?
    return true unless record.role == "admin"
    org.memberships.where(role: :admin).where.not(id: record.id).exists?
  end
end
