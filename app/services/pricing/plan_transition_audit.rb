module Pricing
  class PlanTransitionAudit
    ORGANIZATION_VIOLATION_TYPES = %i[
      seats
      screenshot_projects
      media_storage_bytes
      export_storage_bytes
    ].freeze

    def initialize(user:, target_tier:)
      @user = user
      @target_tier = target_tier.to_s
      @entitlements = Pricing::Entitlements.new(@target_tier)
    end

    def to_h
      {
        target_tier: target_tier,
        blocked_organizations: blocked_organizations,
        organization_violations: organization_violations
      }
    end

    def warning_messages
      messages = []

      if blocked_organizations.any?
        names = blocked_organizations.map { |org| org.name }.join(", ")
        messages << "#{blocked_organizations.count} organization#{'s' if blocked_organizations.count != 1} will be blocked: #{names}."
      end

      organization_violations.each do |violation|
        messages << "#{violation[:organization].name} exceeds the #{feature_name(violation[:type])} limit (#{violation[:current]}/#{violation[:limit]})."
      end

      messages
    end

    def kept_organizations
      @kept_organizations ||= user.owned_organizations.order(:created_at, :id).limit(entitlements.max_owned_organizations).to_a
    end

    def blocked_organizations
      @blocked_organizations ||= begin
        kept_ids = kept_organizations.map(&:id)
        scope = user.owned_organizations.order(:created_at, :id)
        kept_ids.any? ? scope.where.not(id: kept_ids).to_a : scope.to_a
      end
    end

    def organization_violations
      @organization_violations ||= kept_organizations.flat_map do |organization|
        build_organization_violations(organization)
      end
    end

    private

    attr_reader :user, :target_tier, :entitlements

    def build_organization_violations(organization)
      violations = []

      add_violation(
        violations,
        organization: organization,
        type: :seats,
        current: organization.seat_usage_count,
        limit: entitlements.max_seats_per_organization
      )

      add_violation(
        violations,
        organization: organization,
        type: :screenshot_projects,
        current: organization.screenshot_projects.count,
        limit: entitlements.max_screenshot_projects_per_organization
      )

      add_violation(
        violations,
        organization: organization,
        type: :media_storage_bytes,
        current: ScreenshotProject.org_media_storage_bytes(organization.id),
        limit: entitlements.max_media_storage_bytes_per_organization
      )

      add_violation(
        violations,
        organization: organization,
        type: :export_storage_bytes,
        current: ScreenshotProject.org_export_storage_bytes(organization.id),
        limit: entitlements.max_export_storage_bytes_per_organization
      )

      violations
    end

    def add_violation(violations, organization:, type:, current:, limit:)
      return unless current > limit

      violations << {
        organization: organization,
        type: type,
        current: current,
        limit: limit
      }
    end

    def feature_name(type)
      case type.to_sym
      when :seats then "seat"
      when :screenshot_projects then "screenshot project"
      when :media_storage_bytes then "media storage"
      when :export_storage_bytes then "export storage"
      else type.to_s.humanize.downcase
      end
    end
  end
end
