class BillingSubscription < ApplicationRecord
  belongs_to :user

  enum :status, {
    pending: "pending",
    trialing: "trialing",
    active: "active",
    past_due: "past_due",
    paused: "paused",
    cancelled: "cancelled",
    expired: "expired",
    failed: "failed"
  }, prefix: true

  enum :plan_tier, {
    free: "free",
    pro: "pro",
    team: "team"
  }, prefix: true

  enum :billing_interval, {
    monthly: "monthly",
    yearly: "yearly"
  }, prefix: true

  validates :provider, presence: true
  validates :provider_subscription_id, presence: true, uniqueness: { scope: :provider }
  validates :plan_tier, presence: true
  validates :billing_interval, presence: true
  validates :status, presence: true

  scope :most_recent_first, -> { order(created_at: :desc) }
  scope :active_for_entitlements, -> { where(status: %w[trialing active past_due]) }
  scope :current_first, -> {
    order(
      Arel.sql("CASE status WHEN 'active' THEN 0 WHEN 'trialing' THEN 1 WHEN 'past_due' THEN 2 WHEN 'pending' THEN 3 WHEN 'paused' THEN 4 ELSE 5 END"),
      created_at: :desc
    )
  }

  def self.current_for(user)
    where(user: user).current_first.first
  end

  def effective_tier
    (status_trialing? || status_active? || status_past_due?) ? plan_tier : "free"
  end

  def active_or_pending?
    status_trialing? || status_active? || status_past_due? || status_pending?
  end

  def scheduled_change
    provider_payload["scheduled_change"] || {}
  end

  def scheduled_change_action
    scheduled_change["action"].presence
  end

  def scheduled_change_effective_at
    value = scheduled_change["effective_at"]
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def scheduled_change_offering
    Billing::PlanCatalog.fetch_by_price_id(scheduled_change_price_id)
  end

  def scheduled_change_target_tier
    scheduled_change_offering&.fetch(:plan_tier, nil)
  end

  def scheduled_change_target_interval
    scheduled_change_offering&.fetch(:billing_interval, nil)
  end

  def scheduled_change_price_id
    item = Array(scheduled_change["items"]).first || {}
    item.dig("price", "id") || item["price_id"]
  end

  def scheduled_change_cancel?
    scheduled_change["action"] == "cancel"
  end

  def scheduled_plan_change?
    return false if scheduled_change_cancel?

    scheduled_change_offering.present? && scheduled_change_effective_at.present?
  end

  def schedule_kind
    return :cancel if scheduled_change_cancel?
    return :downgrade if scheduled_plan_change?

    nil
  end

  def scheduled_downgrade?
    return false unless scheduled_plan_change?

    target_plan_index.present? && current_plan_index.present? && target_plan_index < current_plan_index
  end

  def scheduled_same_tier_interval_change?
    return false unless scheduled_plan_change?

    scheduled_change_target_tier == effective_tier && scheduled_change_target_interval != billing_interval
  end

  def scheduled_change_matches?(tier:, interval:)
    return false unless scheduled_plan_change?

    scheduled_change_target_tier == tier.to_s && scheduled_change_target_interval == interval.to_s
  end

  def self.recalculate_user_plan!(user)
    previous_tier = user.plan_tier
    active_tiers = where(user: user).active_for_entitlements.pluck(:plan_tier)
    next_tier =
      if active_tiers.include?("team")
        "team"
      elsif active_tiers.include?("pro")
        "pro"
      else
        "free"
      end

    user.update!(plan_tier: next_tier) if user.plan_tier != next_tier

    # If a real Paddle subscription has taken over, clear the reverse-trial
    # fields so we stop showing "trial" UI and stop auto-downgrading them.
    # We only clear when the user has landed on a paid tier; a subscription
    # being cancelled/paused (next_tier == "free") means the trial expiration
    # path (TrialExpirationJob) is the appropriate downgrade trigger -- but
    # typically the trial has already expired by then anyway.
    if next_tier != "free" && user.trial_ends_at.present?
      user.update_columns(trial_started_at: nil, trial_ends_at: nil)
    end

    Pricing::PlanEnforcer.new(user).apply!

    # Audit plan transitions on each of the user's owned orgs. Direction is
    # determined by PLAN_SEQUENCE index; no-op transitions skip logging.
    if previous_tier != next_tier
      log_plan_transition_audit(user: user, from_tier: previous_tier, to_tier: next_tier)
    end

    next_tier
  end

  # Records plan_upgraded or plan_downgraded audit events for each of the
  # user's owned organizations. Uses the PLAN_SEQUENCE ordering to decide
  # direction. Called from recalculate_user_plan! which runs in a Paddle
  # webhook job (no request context), so we pass actor/organization
  # explicitly.
  def self.log_plan_transition_audit(user:, from_tier:, to_tier:)
    prev_idx = Pricing::Entitlements::PLAN_SEQUENCE.index(from_tier.to_s)
    next_idx = Pricing::Entitlements::PLAN_SEQUENCE.index(to_tier.to_s)
    return if prev_idx.nil? || next_idx.nil?

    action = next_idx > prev_idx ? "plan_upgraded" : "plan_downgraded"

    user.owned_organizations.find_each do |org|
      Audit::Logger.log(
        action: action,
        actor: user,
        organization: org,
        metadata: { from: from_tier.to_s, to: to_tier.to_s }
      )
    end

    BillingNotificationJob.perform_later(
      user_id: user.id,
      event: "plan_changed",
      metadata: { from: from_tier.to_s, to: to_tier.to_s }
    )
  end

  # Records a schedule_cleared audit event for each of the user's owned
  # organizations. Called from Billing::Paddle::ScheduledChangesController
  # after Paddle confirms the scheduled_change was nulled. Mirrors
  # log_plan_transition_audit's per-org-fan-out pattern so audit log views
  # (which scope by organization) show these on every relevant org.
  #
  # Falls back to the user's first membership org when they own zero
  # organizations (e.g. a Team-tier invite-only user who somehow holds a
  # personal paid subscription). This prevents silent audit gaps that
  # would undermine abuse detection.
  def self.log_schedule_cleared_audit(user:, schedule_kind:)
    orgs = user.owned_organizations.to_a
    orgs = user.organizations.limit(1).to_a if orgs.empty?

    if orgs.empty?
      Rails.logger.warn("[BillingSubscription] log_schedule_cleared_audit skipped: user=#{user.id} has no organizations")
      return
    end

    orgs.each do |org|
      Audit::Logger.log(
        action: "schedule_cleared",
        actor: user,
        organization: org,
        metadata: { schedule_kind: schedule_kind.to_s }
      )
    end
  end

  private

  def current_plan_index
    Pricing::Entitlements::PLAN_SEQUENCE.index(effective_tier.to_s)
  end

  def target_plan_index
    Pricing::Entitlements::PLAN_SEQUENCE.index(scheduled_change_target_tier.to_s)
  end
end
