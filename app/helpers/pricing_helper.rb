module PricingHelper
  SUPPORT_EMAIL = "support@mysigner.dev".freeze

  # Rendered on /pricing (pricing/_faq) and emitted as FAQPage JSON-LD there,
  # so the structured data always matches the visible content.
  PRICING_FAQS = [
    { q: "What happens when my trial ends?",
      a: "Your account automatically downgrades to Free. We never charge you without explicit opt-in." },
    { q: "Can I switch plans mid-month?",
      a: "Yes — upgrades apply immediately with prorated charges. Downgrades take effect at your next renewal so you keep access to what you've already paid for." },
    { q: "Is there a discount for non-profits or students?",
      a: "Reach out to support@mysigner.dev — we offer discounts case-by-case." },
    { q: "How does seat billing work on Team?",
      a: "Team includes up to 10 seats per organization at the base price. We'll reach out directly if you need more." },
    { q: "Which payment methods do you accept?",
      a: "All major credit/debit cards, Apple Pay, Google Pay, and region-specific methods via Paddle. Wire transfer available on annual Team plans." },
    { q: "Can I self-host or use on-prem?",
      a: "Not today. MySigner is a hosted SaaS. Reach out if on-prem is a hard requirement and we'll share roadmap details." }
  ].freeze

  def pricing_badge_class(tier)
    case tier.to_s
    when "team"
      "badge-secondary"
    when "pro"
      "badge-primary"
    else
      "badge-ghost"
    end
  end

  def pricing_upgrade_mailto(required_plan:, organization: nil, current_plan: nil, feature: nil, source: nil)
    org = organization || current_organization
    # Resolve current plan from explicit value -> org owner's plan -> free.
    # We intentionally do NOT fall back to current_user.plan_tier: a member of an
    # org on Team inherits Team features regardless of their personal plan.
    current = current_plan.presence || org&.plan_tier || "free"
    requested = required_plan.presence || org&.entitlements&.next_plan_tier

    subject = requested.present? ? "MySigner upgrade request" : "MySigner plan support request"
    body_lines = [
      "Hi MySigner team,",
      "",
      (requested.present? ? "I'd like to upgrade my account." : "I'd like help with plan options for my account."),
      "",
      "Current plan: #{current.to_s.titleize}",
      ("Requested plan: #{requested.to_s.titleize}" if requested.present?),
      ("Organization: #{org.name}" if org.present?),
      ("Feature needed: #{feature}" if feature.present?),
      ("Source: #{source}" if source.present?),
      ("User email: #{current_user.email}" if current_user&.email.present?),
      "",
      "Please let me know the next steps."
    ].compact

    "mailto:#{SUPPORT_EMAIL}?subject=#{ERB::Util.url_encode(subject)}&body=#{ERB::Util.url_encode(body_lines.join("\n"))}"
  end

  def pricing_overage_status(organization)
    return nil if organization.blank?

    @pricing_overage_status_cache ||= {}
    cache_key = [ organization.id, organization.updated_at&.to_i, organization.plan_tier ].join(":")

    @pricing_overage_status_cache[cache_key] ||= Pricing::OrganizationOverageStatus.new(organization)
  end
end
