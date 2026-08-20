module Aso
  # Pauses excess TrackedKeywordCountry rows when an org downgrades to a tier
  # with a lower max_tracked_keywords_per_app. Pauses oldest-first by TKC
  # created_at -- users keep their most-recent keyword-country pairs active,
  # because recently-added tracking is usually the most relevant to them.
  #
  # Operates at the TrackedKeywordCountry level (not TrackedKeyword) so a
  # multi-country keyword can have some countries active and some paused
  # instead of all-or-nothing. The rank-check scheduler already filters on
  # `tracked_keyword_countries.enabled = true` + `tracked_keywords.enabled
  # = true`, so setting enabled=false here immediately stops rank checks
  # for those rows without any other wiring change.
  #
  # Idempotent: a second call on an already-pruned org is a no-op because
  # the active count is already at-or-below the new tier's limit.
  class PlanDowngradePruner
    def self.call(organization:)
      new(organization: organization).call
    end

    def initialize(organization:)
      @organization = organization
    end

    def call
      new_limit = @organization.entitlements.max_tracked_keywords_per_app

      @organization.apple_apps.find_each do |app|
        active_scope = TrackedKeywordCountry
          .joins(:tracked_keyword)
          .where(tracked_keywords: { apple_app_id: app.id, enabled: true })
          .where(tracked_keyword_countries: { enabled: true })

        active_count = active_scope.count
        next if active_count <= new_limit

        excess_ids = active_scope
          .order("tracked_keyword_countries.created_at ASC, tracked_keyword_countries.id ASC")
          .limit(active_count - new_limit)
          .pluck("tracked_keyword_countries.id")

        TrackedKeywordCountry.where(id: excess_ids).update_all(
          enabled: false,
          updated_at: Time.current
        )
      end
    end
  end
end
