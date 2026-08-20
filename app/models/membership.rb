class Membership < ApplicationRecord
  belongs_to :user
  belongs_to :organization, counter_cache: true

  enum :role, { admin: 0, developer: 1, viewer: 2 }

  validates :user_id, uniqueness: { scope: :organization_id }

  validate :organization_seat_limit, on: :create
  validate :owner_cannot_be_changed_via_membership, on: :update

  before_destroy :prevent_destroy_if_owner
  before_destroy :prevent_destroy_if_last_admin

  private

  def owner_cannot_be_changed_via_membership
    return unless organization.owner_id == user_id
    errors.add(:base, "Owner cannot be changed via membership") if changed?
  end
  def prevent_destroy_if_owner
    if organization.owner_id == user_id
      errors.add(:base, "Owner membership cannot be removed")
      throw :abort
    end
  end

  def prevent_destroy_if_last_admin
    return true unless role == "admin"
    if organization.memberships.where(role: :admin).where.not(id: id).none?
      errors.add(:base, "Organization must have at least one admin")
      throw :abort
    end
  end

  def organization_seat_limit
    return unless organization

    limit = organization.seat_limit
    return if organization.seat_usage_count < limit

    errors.add(
      :base,
      :quota_exhausted,
      message: "Organization has reached the maximum of #{limit} seats on the #{organization.plan_tier.titleize} plan",
      feature: :seats,
      current_plan: organization.plan_tier,
      next_plan: organization.entitlements.next_plan_that_raises(:max_seats_per_organization)
    )
  end
end
