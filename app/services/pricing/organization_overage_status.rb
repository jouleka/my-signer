module Pricing
  class OrganizationOverageStatus
    attr_reader :organization, :entitlements

    def initialize(organization, tier: nil, entitlements: nil)
      @organization = organization
      @entitlements = entitlements || (tier.present? ? Pricing::Entitlements.new(tier) : Pricing::Entitlements.for_organization(organization))
    end

    def any?
      sections.any?
    end

    def sections
      @sections ||= [
        seats_section,
        screenshot_projects_section,
        media_storage_section,
        export_storage_section
      ].compact
    end

    def seats_overage
      overage_for(organization.seat_usage_count, entitlements.max_seats_per_organization)
    end

    def screenshot_projects_overage
      overage_for(organization.screenshot_projects.count, entitlements.max_screenshot_projects_per_organization)
    end

    def media_storage_overage
      overage_for(
        ScreenshotProject.org_media_storage_bytes(organization.id),
        entitlements.max_media_storage_bytes_per_organization
      )
    end

    def export_storage_overage
      overage_for(
        ScreenshotProject.org_export_storage_bytes(organization.id),
        entitlements.max_export_storage_bytes_per_organization
      )
    end

    def overflow_screenshot_projects
      @overflow_screenshot_projects ||= screenshot_projects_for_current_plan.drop(screenshot_project_limit)
    end

    def kept_screenshot_projects
      @kept_screenshot_projects ||= screenshot_projects_for_current_plan.first(screenshot_project_limit)
    end

    def project_overflow?(project)
      overflow_screenshot_project_ids.include?(project.id)
    end

    def to_h
      {
        any: any?,
        seats: seats_overage.positive?,
        screenshot_projects: screenshot_projects_overage.positive?,
        media_storage: media_storage_overage.positive?,
        export_storage: export_storage_overage.positive?,
        frozen_project_ids: overflow_screenshot_project_ids
      }
    end

    private

    def overage_for(current, limit)
      [ current.to_i - limit.to_i, 0 ].max
    end

    def screenshot_project_limit
      entitlements.max_screenshot_projects_per_organization.to_i
    end

    def screenshot_projects_for_current_plan
      @screenshot_projects_for_current_plan ||= organization.screenshot_projects.order(:created_at, :id).to_a
    end

    def overflow_screenshot_project_ids
      @overflow_screenshot_project_ids ||= overflow_screenshot_projects.map(&:id)
    end

    def seats_section
      return nil unless seats_overage.positive?

      {
        key: :seats,
        title: "Seats",
        badge: "#{seats_overage} over",
        summary: "You have #{organization.memberships.count} active members and #{organization.organization_invitations.active.count} pending invitations against a limit of #{entitlements.max_seats_per_organization} seats.",
        detail: "Remove members or cancel invitations to get back under the plan."
      }
    end

    def screenshot_projects_section
      return nil unless screenshot_projects_overage.positive?

      {
        key: :screenshot_projects,
        title: "Screenshot projects",
        badge: "#{screenshot_projects_overage} over",
        summary: "You have #{organization.screenshot_projects.count} projects and a limit of #{entitlements.max_screenshot_projects_per_organization}. The oldest #{kept_screenshot_projects.size} project#{'s' unless kept_screenshot_projects.size == 1} stay within the plan.",
        detail: "Overflow projects stay visible, but they are the ones above this plan limit.",
        overflow_projects: overflow_screenshot_projects
      }
    end

    def media_storage_section
      return nil unless media_storage_overage.positive?

      {
        key: :media_storage_bytes,
        title: "Screenshot media storage",
        badge: "#{ActiveSupport::NumberHelper.number_to_human_size(media_storage_overage)} over",
        summary: "You are using #{ActiveSupport::NumberHelper.number_to_human_size(ScreenshotProject.org_media_storage_bytes(organization.id))} out of #{ActiveSupport::NumberHelper.number_to_human_size(entitlements.max_media_storage_bytes_per_organization)}.",
        detail: "Remove screenshot images or upgrade to unlock more media storage."
      }
    end

    def export_storage_section
      return nil unless export_storage_overage.positive?

      {
        key: :export_storage_bytes,
        title: "Screenshot export storage",
        badge: "#{ActiveSupport::NumberHelper.number_to_human_size(export_storage_overage)} over",
        summary: "You are using #{ActiveSupport::NumberHelper.number_to_human_size(ScreenshotProject.org_export_storage_bytes(organization.id))} out of #{ActiveSupport::NumberHelper.number_to_human_size(entitlements.max_export_storage_bytes_per_organization)}.",
        detail: "Delete exports or upgrade to keep generating new ones."
      }
    end
  end
end
