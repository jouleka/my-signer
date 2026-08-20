class StoreListingPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(organization_id: user.organizations.select(:id))
    end
  end

  def show?
    member_of_organization?
  end

  def edit?
    developer_or_higher?
  end

  def update?
    developer_or_higher?
  end

  def sync?
    developer_or_higher?
  end

  def push?
    developer_or_higher?
  end

  def translate?
    developer_or_higher?
  end

  def add_locale?
    developer_or_higher?
  end

  def destroy?
    admin_or_owner?
  end

  private

  def organization
    record.organization
  end

  def member_of_organization?
    organization.accessible? && organization.memberships.exists?(user_id: user.id)
  end

  def developer_or_higher?
    return false unless member_of_organization?
    membership = organization.memberships.find_by(user_id: user.id)
    organization.owner_id == user.id || membership&.role.in?(%w[admin developer])
  end

  def admin_or_owner?
    return false unless member_of_organization?
    membership = organization.memberships.find_by(user_id: user.id)
    organization.owner_id == user.id || membership&.role == "admin"
  end
end
