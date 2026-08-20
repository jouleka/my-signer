class TrackedKeywordPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      return scope.none unless user

      accessible_org_ids = OrganizationPolicy::Scope.new(user, Organization).resolve.select(:id)
      scope.joins(:apple_app).where(apple_apps: { organization_id: accessible_org_ids })
    end
  end

  def show?
    user_in_org? && entitlement?
  end

  def create?
    show?
  end

  def destroy?
    user_in_org?  # no entitlement check — allow cleanup after downgrade
  end

  private

  def org
    case record
    when TrackedKeyword then record.apple_app.organization
    when AppleApp       then record.organization
    when Organization   then record
    end
  end

  def user_in_org?
    return false unless user && org
    return false if org.respond_to?(:accessible?) && !org.accessible?
    org.owner_id == user.id || org.memberships.exists?(user_id: user.id)
  end

  def entitlement?
    org && org.entitlements.keyword_editor_enabled?
  end
end
