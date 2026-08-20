# frozen_string_literal: true

#
# db/seeds/screenshot_demo.rb
#
# Seeds realistic, positive-looking dashboard data for the screenshot user
# so Product Hunt / Reddit / Twitter shots have something visually populated.
#
# Idempotent — safe to re-run; skips records that already exist.
#
# Usage (dev / test ONLY):
#   EMAIL=you@example.com bin/rails runner db/seeds/screenshot_demo.rb
#
# This script writes to a real User row: bumps plan_tier to :team, creates
# fake credentials and audit events. Running it against production or
# staging by accident would mutate a live account, so we hard-fail
# outside of dev / test. EMAIL is required (no default) so a typo can't
# silently land on whichever user is hard-coded.

unless Rails.env.development? || Rails.env.test?
  raise "db/seeds/screenshot_demo.rb is dev/test only — refusing to run in #{Rails.env}"
end

require "securerandom"

def demo_private_key
  [ "-----BEGIN PRIVATE KEY-----", "DEMO", "-----END PRIVATE KEY-----" ].join("\n")
end

EMAIL = ENV["EMAIL"].to_s.strip
abort("❌ EMAIL env var is required (e.g. EMAIL=you@example.com bin/rails runner db/seeds/screenshot_demo.rb)") if EMAIL.empty?

user = User.find_by(email: EMAIL)
abort("❌ User not found: #{EMAIL}") unless user
puts "✓ Found user ##{user.id} (#{user.email})"

# Bump plan to team so every dashboard surface (audit log, SSO, etc.) is unlocked
# for screenshots. If you want to screenshot the Free / Pro tier, change this.
if user.plan_tier != "team"
  user.update_columns(plan_tier: User.plan_tiers[:team])
  puts "  ↑ plan_tier bumped to :team"
end

# ─── Organization & membership ───────────────────────────────────────────────
org = user.owned_organizations.first || begin
  Organization.create!(
    name: "DevThings",
    owner: user,
    slug: "devthings-#{SecureRandom.hex(3)}"
  )
end
puts "✓ Org ##{org.id} (#{org.name})"

# ─── ASC + Play credentials (so the credentials pages aren't bare) ───────────
asc = AppStoreConnectCredential.find_or_create_by!(organization: org, name: "Default ASC Key") do |c|
  c.key_id = "ABCD1234EF"
  c.issuer_id = "00000000-0000-0000-0000-000000000000"
  c.private_key = demo_private_key
  c.team_id = "TEAM12345"
  c.active = true
  c.last_synced_at = 2.hours.ago
  c.last_sync_status = "success"
end
puts "✓ ASC credential ##{asc.id}"

gp = GooglePlayCredential.find_or_create_by!(organization: org, name: "Default Play SA") do |c|
  c.service_account_json = {
    "type" => "service_account",
    "project_id" => "demo-project",
    "private_key_id" => "demo-key-id-#{SecureRandom.hex(8)}",
    "private_key" => demo_private_key,
    "client_email" => "demo-sa@demo-project.iam.gserviceaccount.com",
    "client_id" => "100000000000000000001",
    "auth_uri" => "https://accounts.google.com/o/oauth2/auth",
    "token_uri" => "https://oauth2.googleapis.com/token"
  }.to_json
  c.developer_account_id = "demo-dev-account-#{org.id}"
  c.active = true
  c.last_synced_at = 2.hours.ago
  c.last_sync_status = "success"
end
puts "✓ Google Play credential ##{gp.id}"

# ─── Apple Apps ──────────────────────────────────────────────────────────────
apple_app_specs = [
  { name: "Pocket Notes",   bundle_id: "com.devthings.pocketnotes", sku: "pocketnotes-ios" },
  { name: "Daily Habits",   bundle_id: "com.devthings.dailyhabits", sku: "dailyhabits-ios" },
  { name: "Focus Timer Pro", bundle_id: "com.devthings.focustimer",  sku: "focustimer-ios" }
]

apple_apps = apple_app_specs.map.with_index do |spec, i|
  app = AppleApp.find_by(organization: org, bundle_id: spec[:bundle_id])
  app ||= AppleApp.create!(
    organization: org,
    bundle_id: spec[:bundle_id],
    app_store_id: "demoasid#{org.id}#{i}#{SecureRandom.hex(3)}",
    name: spec[:name],
    sku: spec[:sku]
  )
  app
end
puts "✓ Apple apps: #{apple_apps.map(&:name).join(', ')}"

# ─── Android Apps ────────────────────────────────────────────────────────────
android_app_specs = [
  { package: "com.devthings.pocketnotes", name: "Pocket Notes" },
  { package: "com.devthings.readlater",   name: "ReadLater" }
]

android_apps = android_app_specs.map do |spec|
  AndroidApp.find_or_create_by!(organization: org, package_name: spec[:package]) do |a|
    a.name = spec[:name]
    a.default_language = "en-US"
  end
end
puts "✓ Android apps: #{android_apps.map(&:name).join(', ')}"

# ─── Apple Bundle IDs (parent of profiles) ───────────────────────────────────
apple_apps.each_with_index do |app, i|
  AppleBundleId.find_or_create_by!(organization: org, remote_id: "BUNDLE-#{org.id}-#{i}") do |b|
    b.identifier = app.bundle_id
    b.name = app.name
    b.platform = "IOS"
    b.team_id = "TEAM12345"
  end
end
puts "✓ Bundle IDs"

# ─── Apple Certificates (Distribution + Development) ─────────────────────────
[
  { type: "DISTRIBUTION",   expires_in: 300 },
  { type: "DEVELOPMENT",    expires_in: 280 }
].each_with_index do |spec, i|
  AppleCertificate.find_or_create_by!(organization: org, remote_id: "CERT-#{org.id}-#{i}") do |c|
    c.name = "iPhone #{spec[:type].downcase.titleize}: DevThings LLC"
    c.certificate_type = spec[:type]
    c.serial_number = SecureRandom.hex(8).upcase
    c.platform = "IOS"
    c.status = "ISSUED"
    c.team_id = "TEAM12345"
    c.expires_at = spec[:expires_in].days.from_now
  end
end
puts "✓ Apple certificates (Distribution + Development)"

# ─── Apple Provisioning Profiles ─────────────────────────────────────────────
apple_apps.each_with_index do |app, i|
  AppleProvisioningProfile.find_or_create_by!(organization: org, remote_id: "PROF-#{org.id}-#{i}") do |p|
    p.name = "#{app.name} App Store Profile"
    p.uuid = SecureRandom.uuid.upcase
    p.profile_type = "IOS_APP_STORE"
    p.platform = "IOS"
    p.state = "ACTIVE"
    p.bundle_id_identifier = app.bundle_id
    p.expires_at = 280.days.from_now
    p.team_id = "TEAM12345"
  end
end
puts "✓ Provisioning profiles"

# ─── Apple Devices ───────────────────────────────────────────────────────────
[
  { name: "Jurgen's iPhone 15 Pro",   class: "IPHONE",  platform: "IOS" },
  { name: "Office iPad Pro",          class: "IPAD",    platform: "IOS" },
  { name: "QA iPhone 14",             class: "IPHONE",  platform: "IOS" },
  { name: "Designer's iPhone 13 Mini", class: "IPHONE", platform: "IOS" }
].each_with_index do |spec, i|
  AppleDevice.find_or_create_by!(organization: org, remote_id: "DEV-#{org.id}-#{i}") do |d|
    d.name = spec[:name]
    d.udid = SecureRandom.hex(20)
    d.platform = spec[:platform]
    d.device_class = spec[:class]
    d.status = "ENABLED"
  end
end
puts "✓ Apple devices (4)"

# ─── Android Keystore ────────────────────────────────────────────────────────
# Bypass the keytool validator (it shells out to a real keytool binary
# against the real file). Stub it to a no-op for the duration of the seed.
AndroidKeystore.class_eval do
  alias_method :__orig_validate_credentials_with_keytool!, :validate_credentials_with_keytool!
  def validate_credentials_with_keytool!
    self.expires_at ||= 25.years.from_now.to_date
    self.fingerprint_sha256 ||= SecureRandom.hex(32).scan(/../).join(":").upcase
    true
  end
end

begin
  android_apps.each do |app|
    AndroidKeystore.find_or_create_by!(organization: org, name: "release-#{app.package_name}") do |k|
      k.keystore_file = "demo-keystore-#{app.id}-#{SecureRandom.hex(8)}".b
      k.keystore_password = "encrypted:demo"
      k.key_alias = "release"
      k.key_password = "encrypted:demo"
      k.expires_at = 25.years.from_now
      k.active = true
      k.android_app_id = app.id
      k.fingerprint_sha256 = (SecureRandom.hex(32).scan(/../).join(":").upcase)
    end
  end
ensure
  AndroidKeystore.class_eval do
    alias_method :validate_credentials_with_keytool!, :__orig_validate_credentials_with_keytool!
  end
end
puts "✓ Android keystores"

# ─── Apple builds (release history) ──────────────────────────────────────────
apple_apps.each do |app|
  3.times do |n|
    version = "1.#{n + 4}.0"
    build_no = "#{n + 12}"
    AppleBuild.find_or_create_by!(apple_app_id: app.id, build_id: "BUILD-#{app.id}-#{n}") do |b|
      b.organization = org
      b.version = version
      b.build_number = build_no
      b.processing_state = "VALID"
      b.uploaded_date = (n * 18 + 3).days.ago
      b.expires_at = 90.days.from_now
    end
  end
end
puts "✓ Apple builds (3 per app)"

# ─── App releases (statuses: draft / in_review / live / archived) ────────────
apple_apps.each do |app|
  [ [ "1.4.0", "live" ], [ "1.5.0", "live" ], [ "1.6.0", "in_review" ] ].each do |v, st|
    AppRelease.find_or_create_by!(
      organization: org,
      listable: app,
      version_string: v
    ) do |r|
      r.status = st
    end
  end
end
android_apps.each do |app|
  [ [ "1.2.0", "live" ], [ "1.3.0", "live" ], [ "1.4.0", "live" ] ].each do |v, st|
    AppRelease.find_or_create_by!(
      organization: org,
      listable: app,
      version_string: v
    ) do |r|
      r.status = st
    end
  end
end
puts "✓ App releases"

# ─── Reviews (positive-leaning) ──────────────────────────────────────────────
review_templates = [
  { rating: 5, title: "Game changer", body: "Best notes app I've used in years. Sync just works, no fiddling." },
  { rating: 5, title: "Clean and fast", body: "Replaced 3 other apps with this. The widget alone is worth the price." },
  { rating: 5, title: "Finally", body: "Finally a habit tracker that doesn't feel like homework. Keeps me consistent." },
  { rating: 5, title: "Just works", body: "Does exactly what I want without 50 settings to configure. Recommended." },
  { rating: 5, title: "Love the design", body: "Beautiful UI, smooth animations, and most importantly nothing crashes." },
  { rating: 5, title: "Worth every cent", body: "Bought premium on day one and never looked back. Daily driver." },
  { rating: 5, title: "iCloud sync ❤️", body: "I have it on my iPad and iPhone and the sync is instant. Other apps take note." },
  { rating: 5, title: "Beautiful focus timer", body: "Pomodoro app that actually feels nice to use. The session log is great." },
  { rating: 5, title: "Replaced Notion", body: "For quick notes I prefer this 10x over Notion. Way faster to capture an idea." },
  { rating: 5, title: "Dev replies fast", body: "Reported a bug and it was fixed in the next update. Feels like a real product." },
  { rating: 5, title: "Privacy respecting", body: "No accounts required, no tracking. Refreshing." },
  { rating: 5, title: "Daily driver", body: "Open it 20+ times a day. Habit streaks are genuinely motivating." },
  { rating: 4, title: "Solid app", body: "Almost perfect. Wish there was a folder system for notes. 5 stars when that lands." },
  { rating: 4, title: "Great but...", body: "Love it on iPhone but the iPad layout could use more space for the canvas." },
  { rating: 4, title: "Recommended", body: "Been using for 3 months. Would love a Mac app." },
  { rating: 4, title: "Good for the price", body: "Stable, fast, no ads. The free tier is generous too." },
  { rating: 4, title: "Solid",          body: "Does the job well. Could use Apple Watch support." },
  { rating: 4, title: "Fast",           body: "Snappy across devices. One small ask: bigger fonts in settings." },
  { rating: 5, title: "Migrated from Bear", body: "Finally something simpler than Bear and faster too." },
  { rating: 5, title: "10/10",          body: "Just buy it. You won't regret it." },
  { rating: 5, title: "Replaced Forest", body: "Less gimmicky, more useful. The streak tracking is honest." },
  { rating: 5, title: "Genuinely useful", body: "Don't usually leave reviews but this one earned it. Thank you." },
  { rating: 4, title: "Nice work",      body: "Polished. Hoping for shortcuts integration soon." },
  { rating: 3, title: "OK so far",      body: "Works fine but I'd love to see export to markdown." },
  { rating: 5, title: "Read later that doesn't suck", body: "Fast saving, clean reader, syncs across phones. Way better than the alternatives." },
  { rating: 5, title: "Smooth",         body: "Buttery on Pixel 8. No lag, no jank, no nonsense." },
  { rating: 5, title: "Underrated",     body: "Wish more people knew about this. Fits exactly what I needed." },
  { rating: 5, title: "Quick capture",  body: "The share sheet integration alone is worth it." },
  { rating: 4, title: "Solid Android version", body: "Material You support is great. Just needs a tablet layout." },
  { rating: 5, title: "Best in class",  body: "Tried 4 other apps in this category. This one is the keeper." },
  { rating: 5, title: "Refreshing",     body: "Doesn't try to do everything. Just does this one thing really well." },
  { rating: 5, title: "Clean UX",       body: "Onboarding was 30 seconds and I was already productive." }
]

reviewables = apple_apps + android_apps
review_count = 0

reviewables.each do |target|
  selected = review_templates.shuffle.first(8 + rand(4))
  selected.each_with_index do |t, i|
    days_ago = i * 3 + rand(3)
    review = AppReview.find_or_initialize_by(
      organization: org,
      reviewable_type: target.class.name,
      reviewable_id: target.id,
      remote_id: "REV-#{target.class.name}-#{target.id}-#{i}"
    )
    next if review.persisted?

    review.rating = t[:rating]
    review.title = t[:title]
    review.body = t[:body]
    review.reviewer_name = [ "Sam", "Alex", "Morgan", "Taylor", "Jordan", "Casey", "Jamie", "Riley", "Avery" ].sample + " " + ("A".."Z").to_a.sample + "."
    review.territory = %w[USA GBR CAN DEU FRA AUS NLD].sample
    review.language = %w[en-US en-GB de-DE fr-FR].sample
    review.reviewed_at = days_ago.days.ago
    review.sentiment = t[:rating] >= 4 ? "positive" : "neutral"

    # ~30% have a reply already
    if rand < 0.3
      review.reply_text = "Thanks for the kind words! 🙏 If you've got a feature request, drop it at support@mysigner.dev — we read every email."
      review.reply_posted_at = (days_ago - 1).days.ago
      review.reply_status = "posted"
    end

    review.save!
    review_count += 1
  end
end
puts "✓ App reviews (#{review_count} created)"

# ─── Review response templates ───────────────────────────────────────────────
templates = [
  { name: "Thanks (5★)",          category: "praise",          body: "Thanks for the kind review! Really appreciate it. If there's anything you'd like to see in the next update, drop us a line at support@mysigner.dev." },
  { name: "Bug acknowledgment",   category: "bug_report",      body: "Sorry about the bug. We're tracking it down. Could you email us at support@mysigner.dev with your device model + OS version?" },
  { name: "Feature request",      category: "feature_request", body: "Great suggestion! Logged on the roadmap. We'll reply here when it ships." },
  { name: "Apology + fix shipped", category: "bug_report",     body: "This was a real bug and we just shipped a fix. Update to the latest version and let us know if it's still happening." },
  { name: "Pricing question",      category: "general",        body: "The free tier covers most use cases. Pro adds advanced features. Full breakdown on our pricing page. Happy to answer specific questions over email." }
]

templates.each_with_index do |t, i|
  ReviewResponseTemplate.find_or_create_by!(organization: org, name: t[:name]) do |tmpl|
    tmpl.category = t[:category]
    tmpl.body = t[:body]
    tmpl.position = i
  end
end
puts "✓ Review response templates (5)"

# ─── Tracked keywords + ranking history (for the keyword tracker view) ───────
keyword_pool = [
  { kw: "notes app",        pop: 78, app: 0 },
  { kw: "pocket notes",     pop: 42, app: 0 },
  { kw: "simple notes",     pop: 65, app: 0 },
  { kw: "minimal notes",    pop: 38, app: 0 },
  { kw: "fast notes",       pop: 55, app: 0 },
  { kw: "habit tracker",    pop: 82, app: 1 },
  { kw: "daily habits",     pop: 71, app: 1 },
  { kw: "streak tracker",   pop: 48, app: 1 },
  { kw: "routine app",      pop: 60, app: 1 },
  { kw: "morning routine",  pop: 53, app: 1 },
  { kw: "focus timer",      pop: 75, app: 2 },
  { kw: "pomodoro app",     pop: 68, app: 2 },
  { kw: "deep work timer",  pop: 39, app: 2 },
  { kw: "productivity timer", pop: 45, app: 2 },
  { kw: "study timer",      pop: 62, app: 2 }
]

keyword_pool.each do |entry|
  app = apple_apps[entry[:app]]
  tk = TrackedKeyword.find_or_create_by!(apple_app: app, keyword: entry[:kw]) do |k|
    k.search_popularity = entry[:pop]
    k.search_popularity_updated_at = 1.day.ago
    k.search_popularity_source = "apple_ads_recommendations"
    k.enabled = true
  end

  %w[us gb de fr].each do |country|
    tkc = TrackedKeywordCountry.find_or_create_by!(tracked_keyword: tk, country: country) do |c|
      c.last_checked_at = Time.current
      c.current_rank = rand(3..40)
      c.previous_rank = c.current_rank + rand(-3..6)
      c.competition_count = rand(80..420)
      c.enabled = true
    end

    # 30 days of ranking history per country
    base_rank = tkc.current_rank
    30.times do |d|
      checked = (29 - d).days.ago.to_date
      next if KeywordRanking.exists?(tracked_keyword_country_id: tkc.id, checked_on: checked)
      drift = rand(-2..2)
      rank = [ (base_rank + (29 - d) / 5 + drift), 1 ].max
      KeywordRanking.create!(
        organization: org,
        keyword: entry[:kw],
        rank: rank,
        checked_on: checked,
        tracked_keyword_country_id: tkc.id
      )
    end
  end
end
puts "✓ Tracked keywords + 30 days of rankings × 4 countries"

# ─── Apple Ads Recommendations (for the keyword editor inspiration column) ───
%w[notes capture sync productivity widget routine streak motivation pomodoro deep-work].each_with_index do |kw, i|
  apple_apps.each do |app|
    AppleAdsRecommendation.find_or_create_by!(apple_app: app, keyword: kw) do |r|
      r.search_popularity = 25 + (i * 7) + rand(-5..5)
      r.search_popularity_updated_at = 1.day.ago
      r.bid_amount_micros = (1.5e6).to_i + (i * 1e5).to_i
    end
  end
end
puts "✓ Apple Ads recommendations"

# ─── Analytics: 90 days × all apps, growing trend ────────────────────────────
all_app_records = apple_apps + android_apps
all_app_records.each_with_index do |app, app_idx|
  base = 80 + app_idx * 25
  90.times do |d|
    snapshot_date = (89 - d).days.ago.to_date
    next if AppAnalyticsSnapshot.exists?(
      snapshotable_type: app.class.name,
      snapshotable_id: app.id,
      snapshot_date: snapshot_date
    )

    growth = (d * 6) + rand(-25..25)
    first_time = (base + growth).clamp(20, 5_000)
    redownloads = (first_time * 0.18).to_i
    impressions = (first_time * 21) + rand(-200..200)
    page_views = (impressions * 0.32).to_i
    sessions = (first_time * 4.2).to_i

    AppAnalyticsSnapshot.create!(
      organization: org,
      snapshotable_type: app.class.name,
      snapshotable_id: app.id,
      snapshot_date: snapshot_date,
      first_time_downloads: first_time,
      redownloads: redownloads,
      total_downloads: first_time + redownloads,
      impressions: impressions,
      product_page_views: page_views,
      updates: rand(40..220),
      conversion_rate: BigDecimal((rand(28..52) / 10.0).to_s),
      sessions: sessions,
      active_devices: (first_time * 18).to_i,
      crashes: rand(0..3),
      crash_rate: BigDecimal((rand(1..30) / 100_000.0).to_s),
      anr_rate: BigDecimal((rand(1..15) / 100_000.0).to_s),
      data_source: app.is_a?(AppleApp) ? "asc" : "play",
      retention_day_1: BigDecimal((rand(48..56)).to_s),
      retention_day_7: BigDecimal((rand(28..34)).to_s),
      retention_day_14: BigDecimal((rand(20..26)).to_s),
      retention_day_28: BigDecimal((rand(13..18)).to_s),
      installs: first_time + redownloads,
      deletions: rand(8..40),
      proceeds: BigDecimal((first_time * 0.82).round(2).to_s)
    )
  end
end
puts "✓ Analytics: 90 days × #{all_app_records.size} apps"

# ─── Rating snapshots (for the rating trend chart) ───────────────────────────
all_app_records.each do |app|
  90.times do |d|
    snapshot_date = (89 - d).days.ago.to_date
    next if RatingSnapshot.exists?(
      snapshotable_type: app.class.name,
      snapshotable_id: app.id,
      snapshot_date: snapshot_date
    )
    five = 180 + d * 5 + rand(-10..10)
    four = 60 + d * 1 + rand(-5..5)
    three = 12 + rand(-3..3)
    two = 4 + rand(-2..2)
    one = 2 + rand(-1..1)
    total = five + four + three + two + one
    avg = ((5 * five + 4 * four + 3 * three + 2 * two + 1 * one).to_f / total).round(2)

    RatingSnapshot.create!(
      organization: org,
      snapshotable_type: app.class.name,
      snapshotable_id: app.id,
      snapshot_date: snapshot_date,
      average_rating: BigDecimal(avg.to_s),
      review_count: total,
      rating_5_count: [ five, 0 ].max,
      rating_4_count: [ four, 0 ].max,
      rating_3_count: [ three, 0 ].max,
      rating_2_count: [ two, 0 ].max,
      rating_1_count: [ one, 0 ].max
    )
  end
end
puts "✓ Rating snapshots: 90 days × #{all_app_records.size} apps"

# ─── Custom Product Pages (3 per Apple app, with localizations) ──────────────
apple_apps.each do |app|
  [ "Lifehacker readers", "TikTok campaign", "Search Ads — students" ].each_with_index do |name, i|
    cpp = CustomProductPage.find_or_create_by!(
      organization: org,
      apple_app: app,
      remote_id: "CPP-#{app.id}-#{i}"
    ) do |c|
      c.name = name
      c.visible = true
    end
    version = CustomProductPageVersion.find_or_create_by!(
      custom_product_page: cpp,
      organization: org,
      remote_id: "CPPV-#{app.id}-#{i}"
    ) do |v|
      v.state = "PUBLISHED"
    end
    %w[en-US en-GB de-DE fr-FR es-ES].each_with_index do |loc, li|
      CustomProductPageLocalization.find_or_create_by!(
        custom_product_page_version: version,
        organization: org,
        remote_id: "CPPL-#{app.id}-#{i}-#{li}"
      ) do |l|
        l.locale = loc
        l.promotional_text = "The fastest way to capture an idea before it's gone."
      end
    end
  end
end
puts "✓ Custom Product Pages (3 per Apple app, 5 locales each)"

# ─── Screenshot Projects (no scenes — those need real image data) ────────────
project_specs = [
  { name: "Pocket Notes — Spring",   platform: "ios",     template: "warm_editorial", locales: %w[en-US en-GB de-DE fr-FR es-ES it pt-BR ja] },
  { name: "Daily Habits — v1.6",      platform: "ios",     template: "feature_showcase", locales: %w[en-US es-ES de-DE] },
  { name: "Focus Timer — Holiday",    platform: "ios",     template: "neon_hero",     locales: %w[en-US ja zh-Hans] },
  { name: "Pocket Notes Android",     platform: "android", template: "tech_grid",     locales: %w[en-US fr-FR de-DE pt-BR] },
  { name: "ReadLater Launch",         platform: "android", template: "sunset_showcase", locales: %w[en-US es-ES] },
  { name: "Habits — Welcome Back",    platform: "both",    template: "value_promise", locales: %w[en-US] }
]

project_specs.each do |spec|
  ScreenshotProject.find_or_create_by!(organization: org, name: spec[:name]) do |p|
    p.platform = spec[:platform]
    p.template = spec[:template]
    p.locales  = spec[:locales]
    p.scenes_count = 0
    p.settings = { "device_frame" => "iphone-15-pro", "background_style" => "gradient" }
  end
end
puts "✓ Screenshot projects (#{project_specs.size})"

# ─── Store Listings (so the listing-edit page has content) ───────────────────
# iOS uses: subtitle + keywords + description + promotional_text + whats_new
# Android uses: short_description + description + whats_new (no subtitle/keywords)
apple_apps.each do |app|
  %w[en-US en-GB de-DE fr-FR es-ES].each do |loc|
    StoreListing.find_or_create_by!(
      organization: org,
      listable_type: "AppleApp",
      listable_id: app.id,
      locale: loc
    ) do |l|
      l.app_name = app.name
      l.subtitle = "Capture, focus, ship."
      l.keywords = "notes,capture,fast,sync,minimal,productivity,offline,markdown,quick,clean"
      l.description = "Pocket Notes is built for one thing: getting an idea out of your head and onto your phone before you forget it.\n\nNo accounts. No setup. Open the app, type, done. Sync across devices via iCloud (no servers, ever)."
      l.promotional_text = "Now with Apple Watch dictation."
      l.whats_new = "• Faster cold start\n• Apple Watch dictation\n• Bug fixes from your reports, thank you!"
      l.support_url = "https://devthings.example.com/support"
      l.marketing_url = "https://devthings.example.com"
      l.privacy_policy_url = "https://devthings.example.com/privacy"
      l.sync_status = "synced"
      l.last_synced_at = 3.hours.ago
    end
  end
end
android_apps.each do |app|
  %w[en-US de-DE].each do |loc|
    StoreListing.find_or_create_by!(
      organization: org,
      listable_type: "AndroidApp",
      listable_id: app.id,
      locale: loc
    ) do |l|
      l.app_name = app.name
      l.short_description = "Save articles in one tap. Read them in a clean, distraction-free reader."
      l.description = "ReadLater is the simplest way to save what you're reading and come back to it later, even offline."
      l.whats_new = "• Material You theming\n• Background sync\n• Performance improvements"
      l.support_url = "https://devthings.example.com/support"
      l.privacy_policy_url = "https://devthings.example.com/privacy"
      l.sync_status = "synced"
      l.last_synced_at = 3.hours.ago
    end
  end
end
puts "✓ Store listings"

# ─── TestFlight beta groups (so the TF group screen is populated) ────────────
apple_apps.each_with_index do |app, i|
  TestflightBetaGroup.find_or_create_by!(organization: org, remote_id: "BETA-#{app.id}-internal") do |g|
    g.apple_app_id = app.id
    g.name = "Internal Testers"
    g.is_internal_group = true
    g.public_link_enabled = false
    g.tester_count = rand(4..8)
    g.created_at_remote = 60.days.ago
  end
  TestflightBetaGroup.find_or_create_by!(organization: org, remote_id: "BETA-#{app.id}-external") do |g|
    g.apple_app_id = app.id
    g.name = "Beta Wave 4"
    g.is_internal_group = false
    g.public_link_enabled = true
    g.public_link = "https://testflight.apple.com/join/#{SecureRandom.hex(4)}"
    g.tester_count = rand(80..240)
    g.created_at_remote = 35.days.ago
  end
end
puts "✓ TestFlight beta groups"

# ─── Audit log (Team plan feature — populate it for the screenshot) ──────────
audit_actions = [
  { action: "sso_login",                         type: "User",                   hours: 1 },
  { action: "tracked_keyword_added",             type: "TrackedKeyword",         hours: 3 },
  { action: "store_listing_pushed",              type: "StoreListing",           hours: 6 },
  { action: "release_submitted",                 type: "AppRelease",             hours: 11 },
  { action: "asc_credential_activated",          type: "AppStoreConnectCredential", hours: 18 },
  { action: "google_play_credential_activated",  type: "GooglePlayCredential",   hours: 22 },
  { action: "member_invited",                    type: "Membership",             hours: 26 },
  { action: "member_role_changed",               type: "Membership",             hours: 26 },
  { action: "api_token_created",                 type: "ApiToken",               hours: 32 },
  { action: "release_submitted",                 type: "AppRelease",             hours: 50 },
  { action: "tracked_keyword_added",             type: "TrackedKeyword",         hours: 60 },
  { action: "play_store_pushed",                 type: "AndroidApp",             hours: 72 },
  { action: "store_listing_keywords_updated",    type: "StoreListing",           hours: 88 },
  { action: "sso_login",                         type: "User",                   hours: 100 },
  { action: "keyword_idea_saved",                type: "TrackedKeyword",         hours: 130 },
  { action: "release_submitted",                 type: "AppRelease",             hours: 168 },
  { action: "sso_configuration_created",         type: "SsoConfiguration",       hours: 200 },
  { action: "plan_upgraded",                     type: "User",                   hours: 240 },
  { action: "organization_created",              type: "Organization",           hours: 720 }
]

audit_actions.each_with_index do |a, i|
  AuditEvent.find_or_create_by!(
    organization: org,
    action: a[:action],
    resource_type: a[:type],
    resource_id: i + 1,
    created_at: a[:hours].hours.ago
  ) do |ev|
    ev.actor_id = user.id
    ev.metadata = { "demo" => true, "source" => "screenshot_seed" }
    ev.ip_address = "192.0.2.#{rand(2..250)}"
    ev.user_agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) Safari/605.1"
  end
end
puts "✓ Audit events (#{audit_actions.size})"

# ─── API token: skipped (token_digest is required and complex to fake) ───────
# Create a real one through the UI when you screenshot the API tokens page.

puts ""
puts "─" * 60
puts "✅ Seed complete for #{user.email}"
puts "   Org:                #{org.name} (##{org.id})"
puts "   Apple apps:         #{apple_apps.count}"
puts "   Android apps:       #{android_apps.count}"
puts "   Reviews:            #{org.reload.app_reviews.count}"
puts "   Tracked keywords:   #{TrackedKeyword.where(apple_app: apple_apps).count}"
puts "   Keyword rankings:   #{KeywordRanking.where(organization: org).count}"
puts "   Analytics rows:     #{AppAnalyticsSnapshot.where(organization: org).count}"
puts "   Screenshot projects: #{ScreenshotProject.where(organization: org).count}"
puts "   CPPs:               #{CustomProductPage.where(organization: org).count}"
puts "   Audit events:       #{AuditEvent.where(organization: org).count}"
puts ""
puts "Now log in at http://localhost:3000 with #{user.email} and screenshot away."
