class GooglePlayCredentialPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      return scope.none unless user
      scope.where(organization_id: OrganizationPolicy::Scope.new(user, Organization).resolve.select(:id))
    end
  end

  def create?
    admin_or_owner?
  end

  def destroy?
    admin_or_owner?
  end

  def test?
    admin_or_owner?
  end

  def activate?
    admin_or_owner?
  end

  private

  def admin_or_owner?
    org = record.organization
    return false unless org.accessible?

    org.owner_id == user.id || org.memberships.where(user_id: user.id, role: :admin).exists?
  end
end
