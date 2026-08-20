module Aso
  # Weekly cleanup of KeywordRanking rows older than each org's tier-specific
  # retention window (Free: 7 days, Pro: 90, Team: 365). Wired in
  # config/recurring.yml as `aso_keyword_history_retention`, Sunday 3am UTC.
  #
  # We fan out per-org rather than using a single global cutoff because the
  # max_keyword_history_days entitlement differs by plan tier — a single
  # cut-off would either keep Free-tier rows too long or nuke Team-tier
  # history too aggressively.
  #
  # Deletes happen in batches of 1000 via ActiveRecord::Relation#in_batches so
  # we don't lock the table or blow memory on orgs with many historical rows.
  # delete_all (vs destroy_all) skips callbacks — KeywordRanking doesn't have
  # any destroy-time side effects. The DB-level FK `tracked_keyword_country_id`
  # is nullable (TrackedKeywordCountry#destroy uses dependent: :nullify to
  # preserve history), so bulk deletes from this job are safe: we're removing
  # rankings purely by `checked_on` age, independent of the FK state.
  class KeywordHistoryRetentionJob < ApplicationJob
    queue_as :default

    BATCH_SIZE = 1000

    def perform
      Organization.find_each do |org|
        cutoff = org.entitlements.max_keyword_history_days.days.ago
        KeywordRanking
          .where(organization_id: org.id)
          .where("checked_on < ?", cutoff)
          .in_batches(of: BATCH_SIZE) { |rel| rel.delete_all }
      end
    end
  end
end
