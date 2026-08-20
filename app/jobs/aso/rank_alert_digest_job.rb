module Aso
  # Weekly Team-tier digest of "significant" keyword rank movements. Runs
  # Monday 8am UTC (wired in config/recurring.yml as `aso_rank_alert_digest`).
  #
  # For each organization whose plan has `keyword_rank_alerts_enabled?` (Team
  # only in the current CATALOG), we walk every TrackedKeywordCountry under
  # the org's apple apps, compute an Aso::RankMovement with a 7-day window,
  # and collect the ones that flag `#significant?` — i.e. crossed the top-10
  # or top-50 threshold, or moved more than 5 positions within the top 100.
  #
  # Recipients are the org's admin memberships. The `admin` role is what the
  # Membership enum calls out — the org owner is auto-seeded into that role
  # by Organization#ensure_owner_membership!, so filtering on `role: :admin`
  # naturally includes the owner plus any other admins without needing a
  # separate OR-query for the owner User.
  #
  # Mails go through deliver_now because this job is itself async (Solid
  # Queue), and deliver_later would require ActiveJob to serialize the
  # movement list — which contains RankMovement POROs wrapping AR records
  # that GlobalID can't round-trip. Running the mailer synchronously inside
  # the job keeps serialization simple, and any SMTP-level retry still
  # surfaces as a failed Solid Queue job we can retry.
  class RankAlertDigestJob < ApplicationJob
    queue_as :default

    WINDOW_DAYS = 7

    def perform
      entitled_orgs.find_each do |org|
        # `keyword_rank_alerts_enabled?` is the source of truth; the SQL
        # pre-filter on owner plan_tier narrows the scan, this re-check guards
        # the edge where the tier list and the entitlement flag drift apart.
        next unless org.entitlements.keyword_rank_alerts_enabled?

        movements = compute_significant_movements(org)
        next if movements.empty?

        recipients(org).each do |user|
          Aso::RankAlertMailer.weekly_digest(
            user: user,
            organization: org,
            movements: movements
          ).deliver_now
        end
      end
    end

    private

    # Pre-filter to orgs that can actually receive the digest (Team tier owners)
    # instead of scanning every Organization. Preload the owner so the
    # per-org `entitlements` re-check doesn't fire an N+1 owner lookup.
    def entitled_orgs
      Organization
        .scope_with_optional_tier(Organization.all, :team)
        .includes(:owner)
    end

    def compute_significant_movements(org)
      tkcs = TrackedKeywordCountry
        .joins(tracked_keyword: :apple_app)
        .where(apple_apps: { organization_id: org.id })
        .to_a

      # Batch the historical-ranking lookup across all of the org's TKCs (one
      # query) instead of one query per tkc inside the loop.
      Aso::RankMovement
        .for_many(tkcs, window_days: WINDOW_DAYS)
        .select(&:significant?)
    end

    # Owners + admins receive the digest. Because Organization auto-creates an
    # admin membership for the owner on create (see ensure_owner_membership!),
    # role: :admin covers both cases. Developers/viewers are intentionally
    # excluded — rank-movement alerts are a team-lead-level signal.
    def recipients(org)
      org.memberships.where(role: :admin).includes(:user).map(&:user)
    end
  end
end
