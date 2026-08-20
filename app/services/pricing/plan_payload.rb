module Pricing
  class PlanPayload
    HIGHLIGHTS = {
      "free" => [
        { icon: "fa-mobile-screen", label: "1 app", description: "Solo workflow" },
        { icon: "fa-database", label: "300 MB media", description: "Room to try things" },
        { icon: "fa-image", label: "1 screenshot project", description: "5 scenes" },
        { icon: "fa-arrows-rotate", label: "Daily sync", description: "Store + reviews + manual" }
      ].freeze,
      "pro" => [
        { icon: "fa-cloud-arrow-up", label: "Store uploads", description: "60 per day" },
        { icon: "fa-images", label: "10 screenshot projects", description: "10 scenes each" },
        { icon: "fa-language", label: "100 AI translations", description: "+ 50 AI rewrites / mo" },
        { icon: "fa-chart-line", label: "90-day analytics", description: "Trends + keyword tracking" }
      ].freeze,
      "team" => [
        { icon: "fa-lock", label: "SSO + Audit log", description: "SAML 2.0 + 365-day retention" },
        { icon: "fa-user-group", label: "10 seats per org", description: "RBAC roles" },
        { icon: "fa-building", label: "10 organizations", description: "Agency-ready" },
        { icon: "fa-chart-column", label: "365-day analytics", description: "200 keywords / app" }
      ].freeze
    }.freeze

    def self.capability_highlights(tier)
      HIGHLIGHTS.fetch(tier.to_s) { raise ArgumentError, "Unknown tier: #{tier}" }
    end

    def self.usage_bars(organization:, tier:)
      return [] if organization.nil?

      current_tier = organization.plan_tier.to_s
      tier = tier.to_s
      return [] if Pricing::Entitlements::PLAN_SEQUENCE.index(tier).to_i <
                   Pricing::Entitlements::PLAN_SEQUENCE.index(current_tier).to_i

      entitlements = Pricing::Entitlements.new(tier)
      current_entitlements = Pricing::Entitlements.new(current_tier)
      is_projection = tier != current_tier

      bars_for(organization, entitlements, current_entitlements, is_projection)
    end

    def self.bars_for(org, ent, current_ent, is_projection)
      media_bytes = ScreenshotProject.org_media_storage_bytes(org.id)
      uploads_today = org.screenshot_uploads.last_24_hours.count
      projects_count = org.screenshot_projects.count

      [
        build_bar(
          label: "Media storage",
          current_bytes: media_bytes,
          current_max: current_ent.max_media_storage_bytes_per_organization,
          target_max: ent.max_media_storage_bytes_per_organization,
          unit_bytes: true,
          is_projection: is_projection
        ),
        build_bar(
          label: "Store uploads today",
          current_value: uploads_today,
          current_max: current_ent.max_store_uploads_per_day_per_organization,
          target_max: ent.max_store_uploads_per_day_per_organization,
          unit: "/day",
          is_projection: is_projection
        ),
        build_bar(
          label: "Screenshot projects",
          current_value: projects_count,
          current_max: current_ent.max_screenshot_projects_per_organization,
          target_max: ent.max_screenshot_projects_per_organization,
          unit: "",
          is_projection: is_projection
        )
      ].compact
    end

    def self.build_bar(label:, current_max:, target_max:, is_projection:, current_value: nil, current_bytes: nil, unit: "", unit_bytes: false)
      if unit_bytes
        current = current_bytes.to_i
        max = target_max
        unit = max >= 1.gigabyte ? "GB" : "MB"
        display_current = unit == "GB" ? (current.to_f / 1.gigabyte).round(2) : (current.to_f / 1.megabyte).round
        display_max = unit == "GB" ? (max.to_f / 1.gigabyte).round : (max.to_f / 1.megabyte).round
      else
        current = current_value.to_i
        max = target_max
        display_current = current
        display_max = max
      end

      multiplier = is_projection && current_max.to_i.positive? ? (target_max.to_f / current_max).round(1) : nil

      Pricing::UsageBar.new(
        label: label,
        current: is_projection ? nil : display_current,
        max: display_max,
        unit: unit,
        is_projection: is_projection,
        multiplier: multiplier
      )
    end

    private_class_method :bars_for, :build_bar

    def self.for_organization(organization)
      new(organization).to_h
    end

    def initialize(organization)
      @organization = organization
      @entitlements = organization.entitlements
    end

    def to_h
      overage_status = Pricing::OrganizationOverageStatus.new(organization)
      scheduled_change_impact = Pricing::ScheduledPlanChangeImpact.new(
        user: organization.owner,
        subscription: organization.owner.current_billing_subscription,
        organization: organization
      )

      {
        tier: organization.plan_tier,
        next_tier: entitlements.next_plan_tier,
        entitlements: entitlements.to_h.except(:tier),
        usage: {
          seats: organization.seat_usage_count,
          active_memberships: organization.memberships.count,
          pending_invitations: organization.organization_invitations.active.count,
          screenshot_projects: organization.screenshot_projects.count,
          owned_organizations: organization.owner.owned_organizations.count,
          media_storage_bytes: ScreenshotProject.org_media_storage_bytes(organization.id),
          export_storage_bytes: ScreenshotProject.org_export_storage_bytes(organization.id),
          store_uploads_last_24_hours: organization.screenshot_uploads.last_24_hours.count
        },
        overages: overage_status.to_h,
        scheduled_change_impact: scheduled_change_impact.to_h
      }
    end

    private

    attr_reader :organization, :entitlements
  end
end
