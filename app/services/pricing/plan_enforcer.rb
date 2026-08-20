module Pricing
  class PlanEnforcer
    def initialize(user)
      @user = user
      @entitlements = Pricing::Entitlements.for_user(user)
    end

    def apply!
      user.with_lock do
        enforce_owned_organization_access! if Organization.access_state_supported?
        normalize_last_organization_reference!
      end
    end

    private

    attr_reader :user, :entitlements

    def enforce_owned_organization_access!
      keep_ids = owned_organizations_to_keep.select(:id)
      now = Time.current

      user.owned_organizations.where(id: keep_ids).update_all(
        access_state: Organization.access_states[:active],
        access_blocked_at: nil,
        access_block_reason: nil,
        access_blocked_by_plan_tier: nil
      )

      user.owned_organizations.where.not(id: keep_ids).update_all(
        access_state: Organization.access_states[:plan_blocked],
        access_blocked_at: now,
        access_block_reason: "owned_organization_limit",
        access_blocked_by_plan_tier: user.plan_tier
      )
    end

    def normalize_last_organization_reference!
      return if user.last_organization_id.blank?
      return if user.owned_organizations.accessible.exists?(id: user.last_organization_id)
      return if user.organizations.accessible.exists?(id: user.last_organization_id)

      replacement_id = preferred_accessible_organization_id

      user.update_column(:last_organization_id, replacement_id)
    end

    def owned_organizations_to_keep
      user.owned_organizations.order(:created_at, :id).limit(entitlements.max_owned_organizations)
    end

    def preferred_accessible_organization_id
      user.owned_organizations.accessible.order(:created_at, :id).limit(1).pick(:id) ||
        user.organizations.accessible.order("organizations.created_at ASC, organizations.id ASC").limit(1).pick(:id)
    end
  end
end
