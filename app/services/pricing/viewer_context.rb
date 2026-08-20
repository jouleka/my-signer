module Pricing
  ViewerContext = Struct.new(
    :signed_in,
    :viewer_type,        # :prospect | :free | :pro_trialing | :pro | :team
    :current_tier,       # "free" / "pro" / "team" / nil
    :recommended_tier,   # "pro" / "team" / nil
    :trial_days,         # Integer or nil
    :scheduled_change,   # Hash { from:, to:, effective_at: } or nil
    :usage_bars,         # Hash { "pro" => [UsageBar, ...], "team" => [...] }
    keyword_init: true
  ) do
    def self.build(user:, organization:, subscription:, plan_payload:)
      return prospect_context if user.nil?

      viewer_type = resolve_viewer_type(user, subscription)
      current_tier = resolve_current_tier(viewer_type, user, subscription)

      new(
        signed_in: true,
        viewer_type: viewer_type,
        current_tier: current_tier,
        recommended_tier: recommended_for(current_tier),
        trial_days: viewer_type == :pro_trialing ? user.trial_days_remaining : nil,
        scheduled_change: resolve_scheduled_change(subscription),
        usage_bars: resolve_usage_bars(organization, current_tier)
      )
    end

    def self.prospect_context
      new(
        signed_in: false,
        viewer_type: :prospect,
        current_tier: nil,
        recommended_tier: "pro",
        trial_days: nil,
        scheduled_change: nil,
        usage_bars: { "free" => [], "pro" => [], "team" => [] }
      )
    end

    def self.resolve_viewer_type(user, subscription)
      sub_tier = subscription&.effective_tier
      if subscription.present? && sub_tier && sub_tier != "free"
        sub_tier.to_sym
      elsif user.respond_to?(:on_active_trial?) && user.on_active_trial?
        :pro_trialing
      else
        (user.plan_tier.to_s.presence || "free").to_sym
      end
    end

    def self.resolve_current_tier(viewer_type, user, subscription)
      case viewer_type
      when :pro, :team then subscription&.effective_tier&.to_s || viewer_type.to_s
      when :pro_trialing then "pro"
      when :free then "free"
      else user.plan_tier.to_s.presence || "free"
      end
    end

    def self.recommended_for(current_tier)
      idx = Pricing::Entitlements::PLAN_SEQUENCE.index(current_tier.to_s)
      return "pro" if idx.nil?
      Pricing::Entitlements::PLAN_SEQUENCE[idx + 1]
    end

    def self.resolve_scheduled_change(subscription)
      return nil unless subscription.respond_to?(:scheduled_change) && subscription.scheduled_change.present?

      if subscription.scheduled_change_cancel?
        return {
          kind: :cancel,
          from: subscription.plan_tier,
          to: nil,
          effective_at: subscription.scheduled_change_effective_at
        }
      end

      return nil unless subscription.scheduled_plan_change?

      {
        kind: :downgrade,
        from: subscription.plan_tier,
        to: subscription.scheduled_change_target_tier,
        effective_at: subscription.scheduled_change_effective_at
      }
    end

    def self.resolve_usage_bars(organization, _current_tier)
      return { "free" => [], "pro" => [], "team" => [] } if organization.nil?
      Pricing::Entitlements::PLAN_SEQUENCE.each_with_object({}) do |tier, acc|
        acc[tier] = Pricing::PlanPayload.usage_bars(organization: organization, tier: tier)
      end
    end

    private_class_method :prospect_context, :resolve_viewer_type, :resolve_current_tier,
      :recommended_for, :resolve_scheduled_change, :resolve_usage_bars

    # Instance methods

    def prospect?  = viewer_type == :prospect
    def trialing? = viewer_type == :pro_trialing
    def paid?     = %i[pro team].include?(viewer_type)

    def show_most_popular_on?(tier)
      tier = tier.to_s
      case viewer_type
      when :prospect, :free then tier == "pro"
      when :pro             then tier == "team"
      else                        false
      end
    end
  end
end
