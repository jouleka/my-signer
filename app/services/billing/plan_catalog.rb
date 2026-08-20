module Billing
  class PlanCatalog
    PLANS = {
      "pro" => {
        "monthly" => {
          price_cents: 1200,
          price: BigDecimal("12.00"),
          currency: "USD",
          interval_label: "month",
          label: "Pro monthly"
        },
        "yearly" => {
          price_cents: 9600,
          price: BigDecimal("96.00"),
          currency: "USD",
          interval_label: "year",
          label: "Pro yearly",
          savings_badge: "Save 33%"
        }
      },
      "team" => {
        "monthly" => {
          price_cents: 4900,
          price: BigDecimal("49.00"),
          currency: "USD",
          interval_label: "month",
          label: "Team monthly"
        },
        "yearly" => {
          price_cents: 39000,
          price: BigDecimal("390.00"),
          currency: "USD",
          interval_label: "year",
          label: "Team yearly",
          savings_badge: "Save 34%"
        }
      }
    }.freeze

    class << self
      def offerings
        PLANS.deep_dup.tap do |plans|
          plans.each do |tier, intervals|
            intervals.each do |interval, attrs|
              attrs[:price_id] = Billing::Configuration.paddle_price_id_for(tier: tier, interval: interval)
            end
          end
        end
      end

      def fetch(tier:, interval:)
        tier_key = tier.to_s
        interval_key = interval.to_s
        config = PLANS.fetch(tier_key).fetch(interval_key)
        config.merge(
          plan_tier: tier_key,
          billing_interval: interval_key,
          price_id: Billing::Configuration.paddle_price_id_for(tier: tier_key, interval: interval_key)
        )
      end

      def fetch_by_price_id(price_id)
        return nil if price_id.blank?

        offerings.each do |tier, intervals|
          intervals.each do |interval, attrs|
            return attrs.merge(plan_tier: tier, billing_interval: interval) if attrs[:price_id] == price_id
          end
        end

        nil
      end

      # Keyword-tracking bullet list per tier, pulled from Pricing::Entitlements
      # so per-tier limits stay in sync with the catalog (no hardcoded drift).
      # Used by UiHelper#feature_bullets on the Plan Studio cards.
      def keyword_tracking_bullets(tier)
        entitlements = Pricing::Entitlements.new(tier.to_s)

        keyword_count = entitlements.max_tracked_keywords_per_app
        countries = entitlements.max_countries_per_tracked_keyword
        countries_label = (countries >= 999) ? "all App Store countries" : (countries == 1 ? "1 country" : "#{countries} countries")
        refresh_label = (entitlements.keyword_tracking_refresh_days <= 1) ? "daily refresh" : "weekly refresh"

        bullets = [ "#{keyword_count} tracked keywords, #{countries_label}, #{refresh_label}" ]
        bullets << "Apple Search Ads keyword popularity" if entitlements.apple_ads_integration_enabled?
        bullets << "#{entitlements.max_keyword_history_days}-day rank history"
        bullets << "Rank change alerts" if entitlements.keyword_rank_alerts_enabled?
        bullets << "Priority refresh queue" if entitlements.keyword_tracking_priority_queue?
        bullets
      end
    end
  end
end
