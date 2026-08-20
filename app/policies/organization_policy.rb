class OrganizationPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      return scope.none unless user
      scope.joins(:memberships).where(memberships: { user_id: user.id })
    end
  end

  def show?
    accessible_to_member?
  end

  def status?
    accessible_to_member?
  end

  def validate?
    accessible_to_member?
  end

  def create?
    user.present?
  end

  def update?
    accessible_to_admin_or_owner?
  end

  def destroy?
    owner?
  end

  def manage_members?
    # Update/remove members - admin only
    accessible_to_admin_or_owner?
  end

  def invite_members?
    # Developers can invite, but role is restricted via OrganizationInvitationPolicy
    accessible_to_developer_or_higher?
  end

  def manage_credentials?
    accessible_to_admin_or_owner?
  end

  def sync?
    # Developers can sync - it's just reading from Apple
    accessible_to_developer_or_higher?
  end

  # Allow any member to switch into an organization context
  def switch?
    accessible_to_member?
  end

  # For checking if user can create API tokens
  def manage_api_tokens?
    accessible_to_developer_or_higher?
  end

  # For checking if user can manage resources (devices, profiles, app store releases)
  def manage_resources?
    accessible_to_developer_or_higher?
  end

  # BYOK is a Team-tier feature gated to admin/owner. Two gates apply:
  #   1. Tier: the org's plan must include the BYOK entitlement (Team).
  #   2. Role: the role gate is tighter than `manage_credentials?` because
  #      BYOK changes the cryptographic root for every credential in the org
  #      — a wider blast radius than ordinary credential edits, so
  #      developers/viewers are excluded.
  # Free/Pro orgs see the Team-feature paywall (rendered in the controller).
  def manage_byok?
    accessible_to_admin_or_owner? && byok_entitlement?
  end

  # Clearing/disabling BYOK is allowed on ANY tier (role gate only, NO
  # entitlement gate). An org that enabled BYOK on Team and later downgraded
  # must keep this off-ramp — otherwise its credentials stay wrapped under the
  # customer CMK with no UI way to migrate back to the platform-managed key,
  # and a subsequent CMK revoke would brick all decryption irreversibly.
  # Registering a NEW CMK still requires the Team entitlement (manage_byok?).
  def clear_byok?
    accessible_to_admin_or_owner?
  end

  private

  def member?
    record.memberships.exists?(user_id: user.id)
  end

  def owner?
    record.owner_id == user.id
  end

  def admin_or_owner?
    owner? || record.memberships.where(user_id: user.id, role: :admin).exists?
  end

  def developer_or_higher?
    return false unless member?
    membership = record.memberships.find_by(user_id: user.id)
    owner? || membership&.role.in?([ "admin", "developer" ])
  end

  def accessible_to_member?
    record.accessible? && member?
  end

  def accessible_to_admin_or_owner?
    record.accessible? && admin_or_owner?
  end

  def accessible_to_developer_or_higher?
    record.accessible? && developer_or_higher?
  end

  def viewer?
    membership = record.memberships.find_by(user_id: user.id)
    membership&.role == "viewer"
  end

  def byok_entitlement?
    record.entitlements.byok_enabled?
  end
end
