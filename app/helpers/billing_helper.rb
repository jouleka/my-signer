module BillingHelper
  def billing_default_interval
    "yearly"
  end

  def billing_change_action_label(current_subscription:, target_tier:, target_interval: nil)
    billing_change_option(
      current_subscription: current_subscription,
      target_tier: target_tier,
      target_interval: target_interval
    )&.dig(:label) || "Manage billing"
  end

  def billing_change_option(current_subscription:, target_tier:, target_interval:)
    return nil if current_subscription.blank? || current_user.blank?

    # Note: we intentionally no longer short-circuit on
    # `current_subscription.scheduled_plan_change?`. The policy itself decides
    # which transitions are valid when a schedule is pending (Keep-plan undo,
    # Switch-interval + clear, Team→Pro over a pending cancel).

    cache_key = [
      current_subscription.id,
      current_subscription.updated_at&.to_i,
      target_tier.to_s,
      target_interval.to_s
    ].join(":")

    @billing_change_option_cache ||= {}
    @billing_change_option_cache[cache_key] ||= build_billing_change_option(
      current_subscription: current_subscription,
      target_tier: target_tier,
      target_interval: target_interval
    )
  end

  def billing_subscription_change_notice(subscription)
    return nil if subscription.blank?
    return nil if subscription.scheduled_change_cancel?

    offering = subscription.scheduled_change_offering
    effective_at = subscription.scheduled_change_effective_at
    return nil if offering.blank? || effective_at.blank?

    "#{offering.fetch(:plan_tier).titleize} #{offering.fetch(:billing_interval).titleize} starts on #{l(effective_at, format: :long)}."
  end

  def scheduled_plan_change_impact(subscription, organization: nil, only_if_affected: false)
    return nil if subscription.blank? || current_user.blank?

    cache_key = [
      subscription.id,
      subscription.updated_at&.to_i,
      organization&.id,
      only_if_affected
    ].join(":")

    @scheduled_plan_change_impact_cache ||= {}
    impact = @scheduled_plan_change_impact_cache[cache_key] ||= Pricing::ScheduledPlanChangeImpact.new(
      user: current_user,
      subscription: subscription,
      organization: organization
    )

    return nil unless impact.scheduled_downgrade?
    return impact unless only_if_affected
    return impact if impact.current_organization_blocked? || impact.current_organization_impact.present?

    nil
  end

  def billing_price_label(plan)
    amount = number_to_currency(plan.fetch(:price), unit: "$", precision: 0)
    "#{amount}/#{plan.fetch(:interval_label)}"
  end

  def billing_plan_display(tier:, interval:)
    plan = Billing::PlanCatalog.fetch(tier: tier, interval: interval)
    monthly_plan = Billing::PlanCatalog.fetch(tier: tier, interval: "monthly")
    yearly_plan = Billing::PlanCatalog.fetch(tier: tier, interval: "yearly")

    if interval.to_s == "yearly"
      monthly_equivalent = yearly_plan[:price] / 12

      months_saved = ((monthly_plan[:price] * 12 - yearly_plan[:price]) / monthly_plan[:price]).floor

      {
        amount: billing_currency_value(monthly_equivalent),
        unit_label: "/mo",
        billing_note: "#{billing_price_label(yearly_plan)} billed annually",
        savings_badge: "#{months_saved} months free",
        savings_detail: "Save #{billing_currency_value((monthly_plan[:price] * 12) - yearly_plan[:price])} vs monthly"
      }
    else
      {
        amount: billing_currency_value(plan[:price]),
        unit_label: "/mo",
        billing_note: "Billed monthly",
        savings_badge: yearly_plan[:savings_badge],
        savings_detail: "Save with annual — #{billing_currency_value(yearly_plan[:price] / 12)}/mo"
      }
    end
  end

  def billing_current_plan_summary(subscription)
    return "No active subscription." if subscription.blank?

    summary = "#{subscription.plan_tier.titleize} #{subscription.billing_interval.titleize}"
    return "#{summary} ends on #{l(subscription.cancelled_at, format: :long)}." if subscription.cancel_at_period_end? && subscription.cancelled_at.present?
    return "#{summary} renews on #{l(subscription.current_period_ends_at, format: :long)}." if subscription.current_period_ends_at.present?

    "#{summary} is active."
  end

  def billing_cancellation_summary(subscription)
    return nil if subscription.blank? || subscription.current_period_ends_at.blank?

    if subscription.cancel_at_period_end?
      "Cancellation is already scheduled. Access continues until #{l(subscription.current_period_ends_at, format: :long)}."
    else
      "Cancel before #{l(subscription.current_period_ends_at, format: :long)} to stop the next renewal charge."
    end
  end

  def billing_provider_name
    Billing::Configuration.provider_name
  end

  def billing_self_serve_checkout_available?
    Billing::Configuration.self_serve_checkout_available?
  end

  def billing_checkout_enabled?
    Billing::Configuration.paddle_checkout_ready? && Billing::Configuration.paddle_backend_ready?
  end

  def billing_webhooks_ready?
    Billing::Configuration.paddle_webhooks_ready?
  end

  def billing_setup_banner_text
    if billing_checkout_enabled? && billing_webhooks_ready?
      "Billing is active for this account."
    elsif billing_checkout_enabled?
      "Billing is available, but renewal and cancellation syncing still needs final setup."
    else
      "Self-serve checkout is not available yet. Pricing is final and billing will appear here once setup is complete."
    end
  end

  def billing_subscriber_management_text
    "Existing subscribers can manage payment methods, invoices, and cancellation from their billing center. Supported upgrades and renewal changes stay available in-app."
  end

  def pricing_entitlement_display(value)
    return "Unlimited" if value == 999
    return nil if value == 0 || value == false
    return "Yes" if value == true
    value.to_s
  end

  private

  def billing_currency_value(amount)
    numeric = amount.is_a?(BigDecimal) ? amount : BigDecimal(amount.to_s)
    precision = numeric.frac.zero? ? 0 : 2
    number_to_currency(numeric, unit: "$", precision: precision)
  end

  def build_billing_change_option(current_subscription:, target_tier:, target_interval:)
    policy = Billing::SubscriptionChangePolicy.new(
      current_subscription: current_subscription,
      target_tier: target_tier,
      target_interval: target_interval
    )
    return nil unless policy.supported?

    {
      label: policy.label,
      message: policy.message,
      plan_tier: target_tier.to_s,
      billing_interval: target_interval.to_s,
      price_id: policy.target_price_id,
      scheduled: policy.scheduled_change?,
      immediate: policy.immediate_change?,
      clear_scheduled_change: policy.clear_scheduled_change?,
      items_unchanged: policy.items_unchanged?
    }
  end
end
