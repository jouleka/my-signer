module Aso
  # Re-enables paused TrackedKeywordCountry rows on plan upgrade, oldest-first
  # by TKC created_at, up to the new tier's max_tracked_keywords_per_app. The
  # mirror of Aso::PlanDowngradePruner -- reactivates in the same order rows
  # were paused, so a downgrade-then-reupgrade round trip restores the exact
  # same set of active TKCs (assuming no new ones were added in between).
  #
  # Only considers TKCs whose parent TrackedKeyword is still enabled; a TK
  # fully soft-deleted by other means (enabled=false at the TK level) is not
  # resurrected here.
  #
  # Idempotent: if no paused rows exist, or the org is already at/above the
  # new limit, this is a no-op.
  class PlanUpgradeReactivator
    def self.call(organization:)
      new(organization: organization).call
    end

    def initialize(organization:)
      @organization = organization
    end

    def call
      new_limit = @organization.entitlements.max_tracked_keywords_per_app

      @organization.apple_apps.find_each do |app|
        active_count = TrackedKeywordCountry
          .joins(:tracked_keyword)
          .where(tracked_keywords: { apple_app_id: app.id, enabled: true })
          .where(tracked_keyword_countries: { enabled: true })
          .count

        capacity = new_limit - active_count
        next if capacity <= 0

        paused_ids = TrackedKeywordCountry
          .joins(:tracked_keyword)
          .where(tracked_keywords: { apple_app_id: app.id, enabled: true })
          .where(tracked_keyword_countries: { enabled: false })
          .order("tracked_keyword_countries.created_at ASC, tracked_keyword_countries.id ASC")
          .limit(capacity)
          .pluck("tracked_keyword_countries.id")

        next if paused_ids.empty?

        TrackedKeywordCountry.where(id: paused_ids).update_all(
          enabled: true,
          updated_at: Time.current
        )
      end
    end
  end
end
