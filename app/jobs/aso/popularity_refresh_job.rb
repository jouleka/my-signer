module Aso
  class PopularityRefreshJob < ApplicationJob
    include SyncRunTrackable

    queue_as :default
    # String form so Zeitwerk resolves these lazily — the error classes live
    # inside app/services/aso/apple_ads/client.rb (sibling constants to Client),
    # so referencing them directly here before Client is autoloaded raises
    # NameError at class-definition time.
    retry_on "Aso::AppleAds::TransientError", wait: :polynomially_longer, attempts: 3
    retry_on "Aso::AppleAds::RateLimited", wait: :polynomially_longer, attempts: 5

    def perform(organization_id:)
      organization = Organization.find_by(id: organization_id)
      return unless organization
      return unless organization.entitlements.apple_ads_integration_enabled?

      credential = organization.apple_ads_credential
      return unless credential&.last_successful?

      track_sync_run(organization: organization, job_name: :keywords_popularity) do
        client = Aso::AppleAds::Client.new(credential: credential)

        begin
          organization.apple_apps.find_each do |app|
            refresh_for_app(client, app)
          end
          credential.mark_success!
        rescue Aso::AppleAds::CredentialsInvalid => e
          # Catch at the outer loop level so one bad-credential response
          # aborts the whole run instead of wasting an OAuth hit per app.
          # mark_failure! nulls out last_successful_at so #last_successful?
          # returns false — the connection banner flips to a re-connect
          # CTA and the next PopularityRefreshJob run is skipped until
          # the user rotates credentials.
          credential.mark_failure!(e.message)
        end
      end
    end

    private

    def refresh_for_app(client, app)
      recs = client.recommended_keywords(app_store_id: app.app_store_id)

      now = Time.current
      ActiveRecord::Base.transaction do
        recs.each do |r|
          AppleAdsRecommendation.upsert(
            {
              apple_app_id: app.id,
              keyword: r[:keyword],
              search_popularity: r[:search_popularity],
              bid_amount_micros: r[:bid_amount_micros],
              search_popularity_updated_at: now
            },
            unique_by: [ :apple_app_id, :keyword ]
          )
        end

        tks = app.tracked_keywords
                 .where(enabled: true, keyword: recs.map { |r| r[:keyword] })
                 .index_by(&:keyword)

        recs.each do |r|
          tk = tks[r[:keyword]]
          tk&.update!(search_popularity: r[:search_popularity], search_popularity_updated_at: now)
        end
      end
    end
  end
end
