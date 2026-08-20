module Aso
  class KeywordRankCheckJob < ApplicationJob
    include AdvisoryLockable
    include SyncRunTrackable

    queue_as :aso_scraping
    retry_on Aso::RateLimiter::Exhausted, wait: :polynomially_longer, attempts: 10
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(organization_id:)
      organization = Organization.find_by(id: organization_id)
      return unless organization

      with_advisory_lock("keywords:sync:org:#{organization.id}") do
        track_sync_run(organization: organization, job_name: :keywords_rank) do
          entitlements = organization.entitlements
          next unless entitlements.keyword_tracking_enabled?

          organization.apple_apps.find_each do |app|
            check_app(app, entitlements)
          end
        end
      end
    end

    private

    def check_app(app, entitlements)
      scope = TrackedKeywordCountry.joins(:tracked_keyword)
                                   .includes(:tracked_keyword)
                                   .where(tracked_keywords: { apple_app_id: app.id, enabled: true })
                                   .where(enabled: true)

      scope.find_each do |tkc|
        next if fresh_enough?(tkc, entitlements.keyword_tracking_refresh_days)
        next if already_checked_today?(tkc)

        result = Aso::KeywordChecker.new(
          app: app,
          keyword: tkc.tracked_keyword.keyword,
          country: tkc.country
        ).check

        case result
        when :rate_limited
          raise Aso::RateLimiter::Exhausted, "Apple rate-limited the scrape"
        when :network_error
          Rails.logger.warn(
            event: "aso.rank_check.network_error",
            tkc_id: tkc.id, keyword: tkc.tracked_keyword.keyword, country: tkc.country
          )
          next
        when Hash
          record_result(app, tkc, result)
        end
      end
    end

    def fresh_enough?(tkc, refresh_days)
      tkc.last_checked_at && tkc.last_checked_at > refresh_days.days.ago
    end

    def already_checked_today?(tkc)
      KeywordRanking.exists?(tracked_keyword_country_id: tkc.id, checked_on: Date.current)
    end

    def record_result(app, tkc, result)
      rank = result[:rank]
      total = result[:total_count]

      ActiveRecord::Base.transaction do
        KeywordRanking.create!(
          organization: app.organization,
          keyword: tkc.tracked_keyword.keyword,
          tracked_keyword_country: tkc,
          rank: rank,
          checked_on: Date.current
        )

        tkc.update!(
          previous_rank: tkc.current_rank,
          current_rank: rank,
          competition_count: total,
          last_checked_at: Time.current
        )
      end
    end
  end
end
