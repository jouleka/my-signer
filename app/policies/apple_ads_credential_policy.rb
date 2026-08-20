class AppleAdsCredentialPolicy < ApplicationPolicy
  def new?
    admin_or_owner?
  end

  def create?
    admin_or_owner?
  end

  def edit?
    admin_or_owner?
  end

  def update?
    admin_or_owner?
  end

  def destroy?
    admin_or_owner?
  end

  private

  # Gates all mutations on admin role. Since Organization#ensure_owner_membership!
  # grants the owner role :admin on org create, this check covers "owner + any
  # admin member" in a single Membership lookup (mirrors GooglePlayCredentialPolicy
  # semantics). Developers and viewers are denied.
  #
  # Accepts either an AppleAdsCredential (existing or freshly-built) or an
  # Organization record — the controller passes `@credential` (which has
  # `organization` set even when unpersisted via build_apple_ads_credential),
  # but policy specs also exercise the Organization-direct form.
  def admin_or_owner?
    return false unless user

    org =
      if record.is_a?(AppleAdsCredential)
        record.organization
      elsif record.is_a?(Organization)
        record
      else
        record.try(:organization)
      end
    return false unless org
    return false if org.respond_to?(:accessible?) && !org.accessible?

    org.owner_id == user.id || org.memberships.where(user_id: user.id, role: :admin).exists?
  end
end
