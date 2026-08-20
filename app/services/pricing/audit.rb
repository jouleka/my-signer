module Pricing
  class Audit
    def self.call
      new.call
    end

    def call
      {
        owners: owner_violations,
        organizations: organization_violations
      }
    end

    private

    def owner_violations
      User.includes(:owned_organizations).filter_map do |user|
        entitlements = user.entitlements
        owned_count = user.owned_organizations.count
        next unless owned_count > entitlements.max_owned_organizations

        {
          user: user,
          tier: user.plan_tier,
          limit: entitlements.max_owned_organizations,
          current: owned_count,
          type: :owned_organizations
        }
      end
    end

    def organization_violations
      Organization.includes(:owner).find_each.flat_map do |organization|
        build_organization_violations(organization)
      end
    end

    def build_organization_violations(organization)
      entitlements = organization.entitlements
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
        tier: organization.plan_tier,
        type: type,
        current: current,
        limit: limit
      }
    end
  end
end
