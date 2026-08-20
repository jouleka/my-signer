module Pricing
  class Entitlements
    PLAN_SEQUENCE = %w[free pro team].freeze
    REQUIRED_PLAN_BY_FEATURE = {
      store_uploads: "pro",
      scheduled_sync: "free",
      store_listing_push: "pro",
      ai_translations: "free",
      ai_rewrites: "free",
      release_checklist: "free",
      keyword_editor: "pro",
      keyword_tracking: "free",
      review_monitoring: "free",
      custom_product_pages: "pro",
      response_templates: "pro",
      audit_log: "team",
      rbac: "team",
      sso: "team",
      byok: "team"
    }.freeze

    CATALOG = {
      "free" => {
        max_owned_organizations: 1,
        max_seats_per_organization: 1,
        max_screenshot_projects_per_organization: 1,
        max_screenshot_scenes_per_project: 5,
        store_upload_enabled: false,
        scheduled_sync_enabled: true,
        manual_sync_enabled: true,
        stale_dashboard_sync_enabled: true,
        max_media_storage_bytes_per_organization: 300.megabytes,
        max_export_storage_bytes_per_organization: 500.megabytes,
        max_store_uploads_per_day_per_organization: 0,
        max_store_listing_apps: 1,
        max_store_listing_locales: 1,
        store_listing_push_enabled: false,
        max_ai_translations_per_month: 5,
        max_ai_rewrites_per_month: 3,
        release_checklist_enabled: true,
        release_checklist_read_only: true,
        release_notes_history_enabled: true,
        keyword_editor_enabled: false,
        keyword_editor_read_only: true,
        max_tracked_keywords_per_app: 5,
        max_countries_per_tracked_keyword: 1,
        max_keyword_history_days: 7,
        keyword_tracking_refresh_days: 7,
        keyword_tracking_priority_queue: false,
        keyword_rank_alerts_enabled: false,
        apple_ads_integration_enabled: false,
        review_monitoring_enabled: true,
        max_review_monitoring_apps: 1,
        response_templates_enabled: false,
        custom_product_pages_enabled: false,
        analytics_dashboard_enabled: true,
        max_analytics_history_days: 7,
        audit_log_enabled: false,
        rbac_enabled: false,
        sso_enabled: false,
        byok_enabled: false
      },
      "pro" => {
        max_owned_organizations: 3,
        max_seats_per_organization: 1,
        max_screenshot_projects_per_organization: 10,
        max_screenshot_scenes_per_project: 10,
        store_upload_enabled: true,
        scheduled_sync_enabled: true,
        manual_sync_enabled: true,
        stale_dashboard_sync_enabled: true,
        max_media_storage_bytes_per_organization: 2.gigabytes,
        max_export_storage_bytes_per_organization: 5.gigabytes,
        max_store_uploads_per_day_per_organization: 60,
        max_store_listing_apps: 999,
        max_store_listing_locales: 10,
        store_listing_push_enabled: true,
        max_ai_translations_per_month: 100,
        max_ai_rewrites_per_month: 50,
        release_checklist_enabled: true,
        release_checklist_read_only: false,
        release_notes_history_enabled: true,
        keyword_editor_enabled: true,
        keyword_editor_read_only: false,
        max_tracked_keywords_per_app: 50,
        max_countries_per_tracked_keyword: 3,
        max_keyword_history_days: 90,
        keyword_tracking_refresh_days: 1,
        keyword_tracking_priority_queue: false,
        keyword_rank_alerts_enabled: false,
        apple_ads_integration_enabled: true,
        review_monitoring_enabled: true,
        max_review_monitoring_apps: 5,
        response_templates_enabled: true,
        custom_product_pages_enabled: true,
        analytics_dashboard_enabled: true,
        max_analytics_history_days: 90,
        audit_log_enabled: false,
        rbac_enabled: false,
        sso_enabled: false,
        byok_enabled: false
      },
      "team" => {
        max_owned_organizations: 10,
        max_seats_per_organization: 10,
        max_screenshot_projects_per_organization: 30,
        max_screenshot_scenes_per_project: 15,
        store_upload_enabled: true,
        scheduled_sync_enabled: true,
        manual_sync_enabled: true,
        stale_dashboard_sync_enabled: true,
        max_media_storage_bytes_per_organization: 10.gigabytes,
        max_export_storage_bytes_per_organization: 20.gigabytes,
        max_store_uploads_per_day_per_organization: 300,
        max_store_listing_apps: 999,
        max_store_listing_locales: 999,
        store_listing_push_enabled: true,
        max_ai_translations_per_month: 500,
        max_ai_rewrites_per_month: 200,
        release_checklist_enabled: true,
        release_checklist_read_only: false,
        release_notes_history_enabled: true,
        keyword_editor_enabled: true,
        keyword_editor_read_only: false,
        max_tracked_keywords_per_app: 200,
        max_countries_per_tracked_keyword: 999,
        max_keyword_history_days: 365,
        keyword_tracking_refresh_days: 1,
        keyword_tracking_priority_queue: true,
        keyword_rank_alerts_enabled: true,
        apple_ads_integration_enabled: true,
        review_monitoring_enabled: true,
        max_review_monitoring_apps: 999,
        response_templates_enabled: true,
        custom_product_pages_enabled: true,
        analytics_dashboard_enabled: true,
        max_analytics_history_days: 365,
        audit_log_enabled: true,
        rbac_enabled: true,
        sso_enabled: true,
        byok_enabled: true
      }
    }.freeze

    def self.for_user(user)
      new(user&.plan_tier.presence || "free")
    end

    def self.for_organization(organization)
      for_user(organization&.owner)
    end

    def self.required_plan_for(feature)
      REQUIRED_PLAN_BY_FEATURE.fetch(feature.to_sym)
    end

    def initialize(tier)
      normalized_tier = tier.to_s
      raise ArgumentError, "Unsupported plan tier: #{tier}" unless CATALOG.key?(normalized_tier)

      @tier = normalized_tier
    end

    attr_reader :tier

    def max_owned_organizations
      config.fetch(:max_owned_organizations)
    end

    def max_seats_per_organization
      config.fetch(:max_seats_per_organization)
    end

    def max_screenshot_projects_per_organization
      config.fetch(:max_screenshot_projects_per_organization)
    end

    def max_screenshot_scenes_per_project
      config.fetch(:max_screenshot_scenes_per_project)
    end

    def max_media_storage_bytes_per_organization
      config.fetch(:max_media_storage_bytes_per_organization)
    end

    def max_export_storage_bytes_per_organization
      config.fetch(:max_export_storage_bytes_per_organization)
    end

    def max_store_uploads_per_day_per_organization
      config.fetch(:max_store_uploads_per_day_per_organization)
    end

    def store_upload_enabled?
      config.fetch(:store_upload_enabled)
    end

    def scheduled_sync_enabled?
      config.fetch(:scheduled_sync_enabled)
    end

    def manual_sync_enabled?
      config.fetch(:manual_sync_enabled)
    end

    def stale_dashboard_sync_enabled?
      config.fetch(:stale_dashboard_sync_enabled)
    end

    def max_store_listing_apps
      config.fetch(:max_store_listing_apps)
    end

    def max_store_listing_locales
      config.fetch(:max_store_listing_locales)
    end

    def store_listing_push_enabled?
      config.fetch(:store_listing_push_enabled)
    end

    def max_ai_translations_per_month
      config.fetch(:max_ai_translations_per_month)
    end

    def max_ai_rewrites_per_month
      config.fetch(:max_ai_rewrites_per_month)
    end

    def release_checklist_enabled?
      config.fetch(:release_checklist_enabled)
    end

    def release_checklist_read_only?
      config.fetch(:release_checklist_read_only)
    end

    def release_notes_history_enabled?
      config.fetch(:release_notes_history_enabled)
    end

    def keyword_editor_enabled?
      config.fetch(:keyword_editor_enabled)
    end

    def keyword_editor_read_only?
      config.fetch(:keyword_editor_read_only)
    end

    def max_tracked_keywords_per_app
      config.fetch(:max_tracked_keywords_per_app)
    end

    def keyword_tracking_enabled?
      max_tracked_keywords_per_app > 0
    end

    def max_countries_per_tracked_keyword
      config.fetch(:max_countries_per_tracked_keyword)
    end

    def max_keyword_history_days
      config.fetch(:max_keyword_history_days)
    end

    def keyword_tracking_refresh_days
      config.fetch(:keyword_tracking_refresh_days)
    end

    def keyword_tracking_priority_queue?
      config.fetch(:keyword_tracking_priority_queue)
    end

    def keyword_rank_alerts_enabled?
      config.fetch(:keyword_rank_alerts_enabled)
    end

    def apple_ads_integration_enabled?
      config.fetch(:apple_ads_integration_enabled)
    end

    def review_monitoring_enabled?
      config.fetch(:review_monitoring_enabled)
    end

    def max_review_monitoring_apps
      config.fetch(:max_review_monitoring_apps)
    end

    def response_templates_enabled?
      config.fetch(:response_templates_enabled)
    end

    def custom_product_pages_enabled?
      config.fetch(:custom_product_pages_enabled)
    end

    def analytics_dashboard_enabled?
      config.fetch(:analytics_dashboard_enabled)
    end

    def max_analytics_history_days
      config.fetch(:max_analytics_history_days)
    end

    def audit_log_enabled?
      config.fetch(:audit_log_enabled)
    end

    def rbac_enabled?
      config.fetch(:rbac_enabled)
    end

    def sso_enabled?
      config.fetch(:sso_enabled)
    end

    def byok_enabled?
      config.fetch(:byok_enabled)
    end

    def ai_rewrites_remaining(organization)
      return 0 if max_ai_rewrites_per_month == 0

      # Atomic reset: only one concurrent request can reset the counter
      rows = Organization.where(id: organization.id)
        .where("ai_rewrites_reset_at IS NULL OR ai_rewrites_reset_at < ?", Time.current.beginning_of_month)
        .update_all(ai_rewrites_count: 0, ai_rewrites_reset_at: Time.current)
      organization.reload if rows > 0

      [ max_ai_rewrites_per_month - organization.ai_rewrites_count, 0 ].max
    end

    def ai_translations_remaining(organization)
      return 0 if max_ai_translations_per_month == 0

      # Atomic reset: only one concurrent request can reset the counter
      rows = Organization.where(id: organization.id)
        .where("ai_translations_reset_at IS NULL OR ai_translations_reset_at < ?", Time.current.beginning_of_month)
        .update_all(ai_translations_count: 0, ai_translations_reset_at: Time.current)
      organization.reload if rows > 0

      [ max_ai_translations_per_month - organization.ai_translations_count, 0 ].max
    end

    def paid?
      tier != "free"
    end

    def next_plan_tier
      PLAN_SEQUENCE[PLAN_SEQUENCE.index(tier).to_i + 1]
    end

    # Returns the first tier after the current one that actually raises the
    # given numeric limit. Some limits are flat across adjacent plans (seats
    # stay at 1 across Free and Pro), so suggesting the bare next tier is
    # misleading — users upgrade and find the same cap.
    def next_plan_that_raises(attribute)
      index = PLAN_SEQUENCE.index(tier)
      return nil unless index

      current_value = config.fetch(attribute)
      PLAN_SEQUENCE[(index + 1)..].find do |candidate|
        CATALOG.fetch(candidate).fetch(attribute) > current_value
      end
    end

    def to_h
      {
        tier: tier,
        limits: {
          owned_organizations: max_owned_organizations,
          seats_per_organization: max_seats_per_organization,
          screenshot_projects_per_organization: max_screenshot_projects_per_organization,
          screenshot_scenes_per_project: max_screenshot_scenes_per_project,
          media_storage_bytes_per_organization: max_media_storage_bytes_per_organization,
          export_storage_bytes_per_organization: max_export_storage_bytes_per_organization,
          store_uploads_per_day_per_organization: max_store_uploads_per_day_per_organization,
          store_listing_apps: max_store_listing_apps,
          store_listing_locales: max_store_listing_locales,
          ai_translations_per_month: max_ai_translations_per_month,
          ai_rewrites_per_month: max_ai_rewrites_per_month,
          tracked_keywords_per_app: max_tracked_keywords_per_app,
          review_monitoring_apps: max_review_monitoring_apps,
          analytics_history_days: max_analytics_history_days
        },
        features: {
          store_uploads: store_upload_enabled?,
          scheduled_sync: scheduled_sync_enabled?,
          manual_sync: manual_sync_enabled?,
          stale_dashboard_sync: stale_dashboard_sync_enabled?,
          store_listing_push: store_listing_push_enabled?,
          release_checklist: release_checklist_enabled?,
          release_checklist_read_only: release_checklist_read_only?,
          release_notes_history: release_notes_history_enabled?,
          keyword_editor: keyword_editor_enabled?,
          keyword_editor_read_only: keyword_editor_read_only?,
          keyword_tracking: keyword_tracking_enabled?,
          review_monitoring: review_monitoring_enabled?,
          response_templates: response_templates_enabled?,
          custom_product_pages: custom_product_pages_enabled?,
          analytics_dashboard: analytics_dashboard_enabled?,
          audit_log: audit_log_enabled?,
          rbac: rbac_enabled?,
          sso: sso_enabled?,
          byok: byok_enabled?
        }
      }
    end

    private

    def config
      CATALOG.fetch(tier)
    end
  end
end
