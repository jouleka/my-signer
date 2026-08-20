module Pricing
  class ScheduledPlanChangeImpact
    ImpactedOrganization = Struct.new(:organization, :status, keyword_init: true) do
      def summary
        status.sections.map { |section| "#{section[:title]} #{section[:badge]}" }.join(", ")
      end
    end

    attr_reader :user, :subscription, :organization

    def initialize(user:, subscription:, organization: nil)
      @user = user
      @subscription = subscription
      @organization = organization
    end

    def scheduled_downgrade?
      subscription.present? && subscription.scheduled_downgrade?
    end

    def impactful?
      scheduled_downgrade? && (blocked_organizations.any? || organization_impacts.any?)
    end

    def safe?
      scheduled_downgrade? && !impactful?
    end

    def target_tier
      subscription&.scheduled_change_target_tier
    end

    def target_interval
      subscription&.scheduled_change_target_interval
    end

    def effective_at
      subscription&.scheduled_change_effective_at
    end

    def blocked_organizations
      return [] unless scheduled_downgrade?

      audit.blocked_organizations
    end

    def organization_impacts
      return [] unless scheduled_downgrade?

      @organization_impacts ||= audit.kept_organizations.filter_map do |kept_organization|
        status = Pricing::OrganizationOverageStatus.new(kept_organization, tier: target_tier)
        next unless status.any?

        ImpactedOrganization.new(organization: kept_organization, status: status)
      end
    end

    def current_organization_blocked?
      organization.present? && blocked_organizations.any? { |blocked_organization| blocked_organization.id == organization.id }
    end

    def current_organization_impact
      return nil if organization.blank? || current_organization_blocked?

      organization_impacts.find { |impact| impact.organization.id == organization.id }
    end

    def other_organization_impacts
      return organization_impacts if organization.blank?

      organization_impacts.reject { |impact| impact.organization.id == organization.id }
    end

    def target_entitlements
      return nil unless scheduled_downgrade?

      @target_entitlements ||= Pricing::Entitlements.new(target_tier)
    end

    def to_h
      return nil unless scheduled_downgrade?

      {
        target_tier: target_tier,
        target_interval: target_interval,
        effective_at: effective_at&.iso8601,
        impactful: impactful?,
        blocked_organizations: blocked_organizations.map { |blocked_organization| { id: blocked_organization.id, name: blocked_organization.name } },
        organization_impacts: organization_impacts.map do |impact|
          {
            id: impact.organization.id,
            name: impact.organization.name,
            overages: impact.status.to_h
          }
        end
      }
    end

    private

    def audit
      @audit ||= Pricing::PlanTransitionAudit.new(user: user, target_tier: target_tier)
    end
  end
end
