class OrganizationInvitation < ApplicationRecord
  belongs_to :organization
  belongs_to :inviter, class_name: "User"

  enum :role, { admin: 0, developer: 1, viewer: 2 }

  before_validation :generate_token, on: :create
  before_validation :set_default_expiry, on: :create

  validates :email, presence: true
  validates :token, presence: true, uniqueness: true
  validates :role, presence: true
  validate :organization_seat_limit, on: :create

  scope :active, -> { where(accepted_at: nil, cancelled_at: nil).where("expires_at > ?", Time.current) }

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def acceptance_allowed_for?(user)
    return false unless user

    user.email.to_s.casecmp?(email.to_s)
  end

  def accept!(user)
    transaction do
      organization.with_lock do
        invitation = lock_fresh_record!

        raise "Organization is unavailable on the current plan" unless organization.accessible?
        raise "This invitation is not for your account" unless invitation.acceptance_allowed_for?(user)
        raise "Invitation has been cancelled" if invitation.cancelled_at.present?
        raise "Invitation has already been accepted" if invitation.accepted_at.present?
        raise "Invitation expired" if invitation.expired?

        invitation.update!(accepted_at: Time.current)
        organization.memberships.where(user: user).first_or_create!(role: invitation.role)
      end

      reload
    end
  end

  def cancel!
    transaction do
      organization.with_lock do
        invitation = lock_fresh_record!

        return invitation if invitation.cancelled_at.present?

        raise "Invitation has already been accepted" if invitation.accepted_at.present?
        raise "Invitation expired" if invitation.expired?

        invitation.update!(cancelled_at: Time.current)
      end

      reload
    end
  end

  private

  def lock_fresh_record!
    self.class.lock.find(id)
  end

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(24)
  end

  def set_default_expiry
    self.expires_at ||= 7.days.from_now
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
