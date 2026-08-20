FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "Password123!@#" }
    name { "Test User" }
    plan_tier { :free }
    email_notifications_enabled { true }
    notification_days_before { 30 }
    notify_certificate_expiry { true }
    notify_profile_expiry { true }
    notify_keystore_expiry { true }
    confirmed_at { Time.current }
    onboarding_completed_at { Time.current }
    terms_accepted_at { Time.current }

    trait :pro_plan do
      plan_tier { :pro }
    end

    trait :team_plan do
      plan_tier { :team }
    end

    trait :needs_onboarding do
      onboarding_completed_at { nil }
      onboarding_step { 0 }
    end
  end

  factory :organization do
    sequence(:name) { |n| "Organization #{n}" }
    association :owner, factory: :user
  end

  factory :membership do
    user
    organization
    role { :admin }
  end

  factory :apple_certificate do
    organization
    sequence(:remote_id) { |n| "cert_#{n}" }
    name { "Apple Certificate" }
    certificate_type { "IOS_DEVELOPMENT" }
    expires_at { 30.days.from_now }
    status { "active" }
  end

  factory :apple_provisioning_profile do
    organization
    sequence(:remote_id) { |n| "profile_#{n}" }
    name { "Provisioning Profile" }
    profile_type { "IOS_APP_DEVELOPMENT" }
    expires_at { 30.days.from_now }
    state { "active" }
  end

  factory :android_keystore do
    organization
    sequence(:name) { |n| "keystore_#{n}" }
    keystore_file { "fake_content" }
    keystore_password { "password" }
    expires_at { 30.days.from_now }
    active { true }
  end

  factory :apple_app do
    organization
    sequence(:app_store_id) { |n| "#{1000000000 + n}" }
    sequence(:bundle_id) { |n| "com.example.app#{n}" }
    name { "My iOS App" }
    sku { nil }

    # Simulates an app whose Apple-reported primary locale is en-GB.
    trait :en_gb_primary do
      raw_json {
        {
          "id" => "fake_app_id",
          "type" => "apps",
          "attributes" => {
            "name" => "My iOS App",
            "bundleId" => "com.example.app",
            "primaryLocale" => "en-GB"
          }
        }
      }
    end

    # Simulates an app whose Apple-reported primary locale is de-DE.
    trait :de_de_primary do
      raw_json {
        {
          "attributes" => { "primaryLocale" => "de-DE" }
        }
      }
    end
  end

  factory :android_app do
    organization
    sequence(:package_name) { |n| "com.example.app#{n}" }
    name { "My Android App" }
    default_language { "en-US" }

    # Simulates an Android app whose Google-reported default_language is de-DE.
    trait :de_de_primary do
      default_language { "de-DE" }
    end

    # Simulates Google returning the default_language in underscore format
    # (e.g., "pt_BR") instead of hyphen format ("pt-BR").
    trait :pt_br_primary_underscore do
      default_language { "pt_BR" }
    end
  end

  factory :app_store_version do
    apple_app
    organization { apple_app.organization }
    sequence(:version_id) { |n| "asv-#{n}" }
    sequence(:version_string) { |n| "1.0.#{n}" }
    app_store_state { "PREPARE_FOR_SUBMISSION" }
  end

  factory :apple_build do
    apple_app
    organization { apple_app.organization }
    sequence(:build_id) { |n| "build-#{n}" }
    sequence(:version) { |n| "1.0.#{n}" }
    sequence(:build_number) { |n| "#{n}" }
    processing_state { "VALID" }
    raw_json { {} }
  end

  factory :android_track do
    android_app
    track_name { "production" }
    status { "completed" }
    raw_json { {} }
  end

  factory :play_store_release do
    android_app
    sequence(:version_code) { |n| "#{n}" }
    track { "production" }
    status { "draft" }
    auto_submit { false }
  end

  factory :store_listing do
    organization
    association :listable, factory: :apple_app
    locale { "en-US" }
    app_name { "My App" }
    description { "A great app for everyone." }
    sync_status { "draft" }

    trait :ios do
      association :listable, factory: :apple_app
      subtitle { "The best app" }
      keywords { "productivity,tools,utility" }
      promotional_text { "Try our new features!" }
    end

    trait :android do
      association :listable, factory: :android_app
      organization { listable.organization }
      short_description { "A great app for everyone." }
    end

    trait :synced do
      sync_status { "synced" }
      last_synced_at { 1.hour.ago }
    end

    trait :modified do
      sync_status { "modified" }
      last_synced_at { 1.day.ago }
    end

    trait :needs_review do
      translation_status { "needs_review" }
    end
  end

  factory :app_store_connect_credential do
    organization
    sequence(:name) { |n| "ASC Credential #{n}" }
    key_id { "KEYID123" }
    issuer_id { "ISSUER12345678901234" }
    private_key { "-----BEGIN EC PRIVATE KEY-----\nfake\n-----END EC PRIVATE KEY-----" }
    active { true }
  end

  factory :google_play_credential do
    organization
    sequence(:name) { |n| "GP Credential #{n}" }
    service_account_json { '{"type":"service_account","project_id":"test"}' }
    active { true }
  end

  factory :screenshot_project do
    organization
    sequence(:name) { |n| "Screenshot Project #{n}" }
    platform { "both" }
    settings { {} }
  end

  factory :screenshot_upload do
    screenshot_project
    organization { screenshot_project.organization }
    target { "app_store_connect" }
    status { "pending" }
    config { {} }
    progress { {} }
  end

  factory :screenshot_scene do
    screenshot_project
    sequence(:position) { |n| n }
    caption_text { "Test Caption" }
    subtitle_text { nil }
    source_image_data { "fake_image_data" }
    source_image_content_type { "image/png" }
    source_image_filename { "screenshot.png" }
    source_image_width { 1080 }
    source_image_height { 1920 }
  end

  factory :release_note do
    organization
    association :listable, factory: :apple_app
    locale { "en-US" }
    version_string { "1.0.0" }
    status { "draft" }
    source { "manual" }
    template_data { { "new" => [ "Added dark mode" ], "improved" => [ "Faster loading" ], "fixed" => [ "Crash on startup" ] } }
    rendered_text { "NEW\n- Added dark mode\n\nIMPROVED\n- Faster loading\n\nFIXED\n- Crash on startup" }

    trait :ios do
      association :listable, factory: :apple_app
    end

    trait :android do
      association :listable, factory: :android_app
      rendered_text { "NEW\n- Added dark mode" }
    end

    trait :pending_review do
      status { "pending_review" }
      submitted_for_review_at { Time.current }
    end

    trait :review_requested_changes do
      status { "draft" }
      submitted_for_review_at { 1.hour.ago }
      reviewed_at { 30.minutes.ago }
      association :reviewed_by, factory: :user
      review_comment { "Please be more specific about what was improved." }
    end

    trait :applied do
      status { "applied" }
      applied_at { Time.current }
    end

    trait :published do
      status { "published" }
      applied_at { 1.hour.ago }
      published_at { Time.current }
    end

    trait :archived do
      status { "archived" }
      applied_at { 2.hours.ago }
      published_at { 1.hour.ago }
    end

    trait :ai_rewritten do
      source { "ai_rewrite" }
      raw_input { "fix: resolved crash in photo picker\nfeat: add dark theme support\nperf: optimize image loading" }
    end

    trait :with_translations do
      translations { { "de-DE" => "NEU\n- Dunkelmodus hinzugefuegt", "ja" => "NEW\n- ダークモード追加" } }
    end
  end

  factory :app_release do
    organization
    association :listable, factory: :apple_app
    version_string { "1.0.0" }
    status { "draft" }

    trait :ios do
      association :listable, factory: :apple_app
    end

    trait :android do
      association :listable, factory: :android_app
    end

    trait :in_review do
      status { "in_review" }
    end

    trait :live do
      status { "live" }
    end

    trait :archived do
      status { "archived" }
    end
  end

  factory :keyword_ranking do
    # Post-Phase-C: rankings only join to an app via the tracked_keyword_country
    # FK chain. Test callers should either pass an explicit `tracked_keyword_country`
    # or rely on the factory creating a fresh one alongside its keyword & country.
    organization { tracked_keyword_country&.organization || association(:organization) }
    association :tracked_keyword_country
    keyword { tracked_keyword_country&.tracked_keyword&.keyword || "productivity" }
    rank { 15 }
    checked_on { Date.current }
  end

  factory :tracked_keyword do
    association :apple_app
    sequence(:keyword) { |n| "keyword #{n}" }
    enabled { true }
  end

  factory :tracked_keyword_country do
    association :tracked_keyword
    country { "us" }
    enabled { true }
  end

  factory :app_review do
    organization
    association :reviewable, factory: :apple_app
    sequence(:remote_id) { |n| "review_#{n}" }
    rating { 4 }
    body { "Great app!" }
    reviewer_name { "John D." }
    reviewed_at { 1.day.ago }
    sentiment { "positive" }
    reply_status { "none" }

    trait :negative do
      rating { 1 }
      body { "This app crashes constantly." }
      sentiment { "negative" }
    end

    trait :neutral do
      rating { 3 }
      body { "It's okay, could be better." }
      sentiment { "neutral" }
    end

    trait :android do
      association :reviewable, factory: :android_app
      organization { reviewable.organization }
    end

    trait :with_reply do
      reply_text { "Thank you for your feedback!" }
      reply_status { "posted" }
      reply_posted_at { 1.hour.ago }
    end
  end

  factory :rating_snapshot do
    organization
    association :snapshotable, factory: :apple_app
    snapshot_date { Date.current }
    average_rating { 4.2 }
    review_count { 100 }
    rating_1_count { 5 }
    rating_2_count { 8 }
    rating_3_count { 12 }
    rating_4_count { 35 }
    rating_5_count { 40 }
  end

  factory :review_response_template do
    organization
    name { "Bug Report Response" }
    category { "bug_report" }
    body { "Thanks for reporting this issue. Our team is investigating and we'll release a fix soon." }
    position { 0 }
  end

  factory :custom_product_page do
    organization
    apple_app
    sequence(:remote_id) { |n| "cpp_#{n}" }
    name { "Summer Campaign" }
    visible { true }
  end

  factory :custom_product_page_version do
    custom_product_page
    organization { custom_product_page.organization }
    sequence(:remote_id) { |n| "cppv_#{n}" }
    state { "PREPARE_FOR_SUBMISSION" }

    trait :published do
      state { "PUBLISHED" }
    end
  end

  factory :custom_product_page_localization do
    custom_product_page_version
    organization { custom_product_page_version.organization }
    sequence(:remote_id) { |n| "cppl_#{n}" }
    locale { "en-US" }
    promotional_text { "Check out our summer deals!" }
  end

  factory :release_checklist do
    organization
    association :listable, factory: :apple_app
    version_string { "1.0.0" }
    platform { "ios" }
    items { ReleaseChecklist::DEFAULT_ITEMS.deep_dup }

    trait :all_checked do
      items {
        ReleaseChecklist::DEFAULT_ITEMS.deep_dup.map do |item|
          item.merge("checked" => true, "checked_at" => Time.current.iso8601)
        end
      }
      all_required_complete { true }
    end

    trait :partially_checked do
      items {
        items = ReleaseChecklist::DEFAULT_ITEMS.deep_dup
        items.first["checked"] = true
        items.first["checked_at"] = Time.current.iso8601
        items
      }
    end
  end

  factory :app_analytics_snapshot do
    organization
    association :snapshotable, factory: :apple_app
    snapshot_date { Date.current }
    first_time_downloads { 93 }
    redownloads { 55 }
    total_downloads { 148 }
    impressions { 907 }
    product_page_views { 468 }
    updates { 1910 }
    conversion_rate { 16.3 }
    sessions { 2500 }
    active_devices { 1800 }
    crashes { 3 }
    crash_rate { 0.0012 }
    data_source { "apple_analytics" }
  end

  factory :apple_ads_credential do
    association :organization
    client_id { "SEARCHADS.00000000-0000-0000-0000-000000000000" }
    team_id { "1234567890" }
    key_id { "ABCDEF1234" }
    private_key_pem { SpecCredentialFixtures.ec_private_key }
  end

  factory :apple_ads_recommendation do
    association :apple_app
    sequence(:keyword) { |n| "rec-kw-#{n}" }
    search_popularity { 50 }
    search_popularity_updated_at { Time.current }
    bid_amount_micros { 1_500_000 }
  end

  factory :saved_keyword_idea do
    association :apple_app
    sequence(:keyword) { |n| "saved-idea-#{n}" }
    association :added_by_user, factory: :user
  end

  factory :billing_subscription do
    user
    provider { "paddle" }
    sequence(:provider_subscription_id) { |n| "sub_test_#{n}" }
    plan_tier { :pro }
    billing_interval { :yearly }
    status { :active }
    current_period_ends_at { 30.days.from_now }
    provider_payload do
      {
        "id" => provider_subscription_id,
        "status" => status.to_s,
        "items" => [ { "price" => { "id" => "pri_#{plan_tier}_#{billing_interval}" } } ]
      }
    end
    last_synced_at { Time.current }

    trait :team_yearly do
      plan_tier { :team }
      billing_interval { :yearly }
    end

    trait :with_scheduled_cancel do
      provider_payload do
        {
          "id" => provider_subscription_id,
          "status" => status.to_s,
          "items" => [ { "price" => { "id" => "pri_#{plan_tier}_#{billing_interval}" } } ],
          "scheduled_change" => {
            "action" => "cancel",
            "effective_at" => 30.days.from_now.iso8601
          }
        }
      end
    end

    trait :with_scheduled_pro_downgrade do
      plan_tier { :team }
      billing_interval { :yearly }
      provider_payload do
        {
          "id" => provider_subscription_id,
          "status" => "active",
          "items" => [ { "price" => { "id" => "pri_team_yearly" } } ],
          "scheduled_change" => {
            "action" => "update",
            "items" => [ { "price" => { "id" => "pri_pro_yearly" } } ],
            "effective_at" => 30.days.from_now.iso8601
          }
        }
      end
    end
  end
end
