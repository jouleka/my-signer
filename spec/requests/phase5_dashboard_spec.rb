require "rails_helper"

RSpec.describe "Phase 5 Dashboard", type: :request do
  let(:user) { create(:user, plan_tier: :free) }
  let(:organization) { create(:organization, owner: user) }

  before do
    Rails.cache.clear
    sign_in user, scope: :user
    post switch_organization_path(organization)
  end

  # ─── A. Basic Dashboard Loading ───────────────────────────────────────────────

  describe "basic dashboard loading" do
    it "returns 200 and renders the dashboard heading with org name" do
      get authenticated_root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ship Apple &amp; Android builds without leaving MySigner")
      expect(response.body).to include(organization.name)
    end

    it "shows the org name in the badge and description" do
      get authenticated_root_path

      expect(response.body).to include("Everything #{organization.name} needs")
    end
  end

  # ─── B. Release Status Cards ──────────────────────────────────────────────────

  describe "release status cards" do
    it "shows Release Status section heading" do
      get authenticated_root_path

      expect(response.body).to include("Release Status")
    end

    context "with no apps" do
      it "shows the empty state" do
        get authenticated_root_path

        expect(response.body).to include("No releases yet")
        expect(response.body).to include("Create Release")
      end
    end

    context "with an iOS app that is live" do
      let!(:apple_app) { create(:apple_app, organization: organization, name: "LiveApp", sku: "live-ios-1") }
      let!(:asv) { create(:app_store_version, apple_app: apple_app, organization: organization, app_store_state: "READY_FOR_SALE", version_string: "2.1.0") }

      it "shows the app name, iOS badge, version, and Live status" do
        get authenticated_root_path

        expect(response.body).to include("LiveApp")
        expect(response.body).to include("iOS")
        expect(response.body).to include("v2.1.0")
        expect(response.body).to include("Live")
      end
    end

    context "with an iOS app in review" do
      let!(:apple_app) { create(:apple_app, organization: organization, name: "ReviewApp", sku: "review-ios-1") }
      let!(:asv) { create(:app_store_version, apple_app: apple_app, organization: organization, app_store_state: "IN_REVIEW", version_string: "1.5.0") }

      it "shows In Review status" do
        get authenticated_root_path

        expect(response.body).to include("ReviewApp")
        expect(response.body).to include("In Review")
      end
    end

    context "with a rejected iOS app" do
      let!(:apple_app) { create(:apple_app, organization: organization, name: "RejectedApp", sku: "rejected-ios-1") }
      let!(:asv) { create(:app_store_version, apple_app: apple_app, organization: organization, app_store_state: "REJECTED", version_string: "1.0.0") }

      it "shows Rejected status" do
        get authenticated_root_path

        expect(response.body).to include("RejectedApp")
        expect(response.body).to include("Rejected")
      end
    end

    context "with a draft iOS app" do
      let!(:apple_app) { create(:apple_app, organization: organization, name: "DraftApp", sku: "draft-ios-1") }
      let!(:asv) { create(:app_store_version, apple_app: apple_app, organization: organization, app_store_state: "PREPARE_FOR_SUBMISSION", version_string: "0.9.0") }

      it "shows Draft status" do
        get authenticated_root_path

        expect(response.body).to include("DraftApp")
        expect(response.body).to include("Draft")
      end
    end

    context "with an Android app that is live" do
      let!(:android_app) { create(:android_app, organization: organization, name: "AndroidLive") }
      let!(:release) { create(:play_store_release, android_app: android_app, status: "live", version_code: "42", track: "production", released_at: 1.day.ago) }

      it "shows the app name, Android badge, version, and Live status" do
        get authenticated_root_path

        expect(response.body).to include("AndroidLive")
        expect(response.body).to include("Android")
        expect(response.body).to include("v42")
        expect(response.body).to include("Live")
      end
    end

    context "with an Android app submitted for review" do
      let!(:android_app) { create(:android_app, organization: organization, name: "AndroidSubmitted") }
      let!(:release) { create(:play_store_release, android_app: android_app, status: "submitted", version_code: "10", track: "production") }

      it "shows Submitted status" do
        get authenticated_root_path

        expect(response.body).to include("AndroidSubmitted")
        expect(response.body).to include("Submitted")
      end
    end

    context "with an Android app with staged rollout" do
      let!(:android_app) { create(:android_app, organization: organization, name: "RolloutApp") }
      let!(:release) { create(:play_store_release, android_app: android_app, status: "live", version_code: "55", track: "production", user_fraction: 0.25, released_at: 1.hour.ago) }

      it "shows the rollout percentage" do
        get authenticated_root_path

        expect(response.body).to include("25% rollout")
      end
    end

    context "with an Android app on a non-production track" do
      let!(:android_app) { create(:android_app, organization: organization, name: "BetaApp") }
      let!(:release) { create(:play_store_release, android_app: android_app, status: "draft", version_code: "5", track: "beta") }

      it "shows the track name" do
        get authenticated_root_path

        expect(response.body).to include("beta")
      end
    end

    context "with an iOS app that has no name (falls back to bundle_id)" do
      let!(:apple_app) { create(:apple_app, organization: organization, name: nil, bundle_id: "com.example.fallback", sku: "fallback-ios-1") }
      let!(:asv) { create(:app_store_version, apple_app: apple_app, organization: organization, app_store_state: "READY_FOR_SALE", version_string: "1.0.0") }

      it "falls back to bundle_id when name is blank" do
        get authenticated_root_path

        expect(response.body).to include("com.example.fallback")
      end
    end

    context "with an Android app that has no name (falls back to package_name)" do
      let!(:android_app) { create(:android_app, organization: organization, name: nil, package_name: "com.example.noname") }
      let!(:release) { create(:play_store_release, android_app: android_app, status: "draft", version_code: "1", track: "production") }

      it "falls back to package_name when name is blank" do
        get authenticated_root_path

        expect(response.body).to include("com.example.noname")
      end
    end

    context "with both iOS and Android apps" do
      let!(:apple_app) { create(:apple_app, organization: organization, name: "iOSApp", sku: "multi-ios-1") }
      let!(:asv) { create(:app_store_version, apple_app: apple_app, organization: organization, app_store_state: "READY_FOR_SALE", version_string: "3.0.0") }
      let!(:android_app) { create(:android_app, organization: organization, name: "DroidApp") }
      let!(:release) { create(:play_store_release, android_app: android_app, status: "live", version_code: "100", track: "production", released_at: 1.day.ago) }

      it "shows both iOS and Android apps" do
        get authenticated_root_path

        expect(response.body).to include("iOSApp")
        expect(response.body).to include("DroidApp")
      end
    end
  end

  # ─── C. Analytics Overview ────────────────────────────────────────────────────

  describe "analytics overview" do
    it "shows the Analytics section heading" do
      get authenticated_root_path

      expect(response.body).to include("Analytics")
      expect(response.body).to include("30d")
    end

    context "with no analytics data" do
      it "shows the empty state" do
        get authenticated_root_path

        expect(response.body).to include("No analytics data")
        expect(response.body).to include("View Analytics")
      end
    end

    context "with analytics data" do
      let!(:apple_app) { create(:apple_app, organization: organization, sku: "analytics-ios-1") }

      before do
        # Current 30 days
        create(:app_analytics_snapshot,
               organization: organization,
               snapshotable: apple_app,
               snapshot_date: 5.days.ago.to_date,
               total_downloads: 500,
               impressions: 2000,
               conversion_rate: 18.5,
               crash_rate: 0.5)

        # Previous 30 days
        create(:app_analytics_snapshot,
               organization: organization,
               snapshotable: apple_app,
               snapshot_date: 45.days.ago.to_date,
               total_downloads: 400,
               impressions: 1500,
               conversion_rate: 15.0,
               crash_rate: 0.8)
      end

      it "shows download count" do
        get authenticated_root_path

        expect(response.body).to include("Downloads")
        expect(response.body).to include("500")
      end

      it "shows impression count" do
        get authenticated_root_path

        expect(response.body).to include("Impressions")
        expect(response.body).to include("2,000")
      end

      it "shows conversion rate" do
        get authenticated_root_path

        expect(response.body).to include("Conversion")
        expect(response.body).to include("18.5%")
      end

      it "shows crash rate" do
        get authenticated_root_path

        expect(response.body).to include("Crash Rate")
        expect(response.body).to include("0.5%")
      end

      it "shows percentage change for downloads" do
        get authenticated_root_path

        # (500-400)/400 * 100 = 25.0
        expect(response.body).to include("+25.0%")
      end

      it "shows the Full Report link" do
        get authenticated_root_path

        expect(response.body).to include("Full Report")
      end
    end

    context "with analytics data but no conversion or crash rate" do
      let!(:apple_app) { create(:apple_app, organization: organization, sku: "analytics-no-rate-1") }

      before do
        create(:app_analytics_snapshot,
               organization: organization,
               snapshotable: apple_app,
               snapshot_date: 5.days.ago.to_date,
               total_downloads: 100,
               impressions: 500,
               conversion_rate: nil,
               crash_rate: nil)
      end

      it "shows No data for conversion and crash rate" do
        get authenticated_root_path

        expect(response.body).to include("No data")
      end
    end
  end

  # ─── D. Recent Reviews & Ratings ──────────────────────────────────────────────

  describe "reviews and ratings" do
    it "shows the Reviews & Ratings section heading" do
      get authenticated_root_path

      expect(response.body).to include("Reviews &amp; Ratings")
    end

    context "with no reviews" do
      it "shows the empty state" do
        get authenticated_root_path

        expect(response.body).to include("No reviews yet")
        expect(response.body).to include("Reviews will appear here once your apps receive store feedback.")
      end
    end

    context "with reviews and rating snapshots" do
      let!(:apple_app) { create(:apple_app, organization: organization, name: "RatedApp", sku: "rated-ios-1") }
      let!(:android_app) { create(:android_app, organization: organization, name: "RatedDroid") }

      let!(:apple_snapshot) do
        create(:rating_snapshot,
               organization: organization,
               snapshotable: apple_app,
               snapshot_date: Date.current,
               average_rating: 4.5,
               review_count: 200)
      end

      let!(:android_snapshot) do
        create(:rating_snapshot,
               organization: organization,
               snapshotable: android_app,
               snapshot_date: Date.current,
               average_rating: 3.8,
               review_count: 150)
      end

      let!(:positive_review) do
        create(:app_review,
               organization: organization,
               reviewable: apple_app,
               rating: 5,
               title: "Fantastic app",
               body: "Love using this every day!",
               reviewer_name: "Alice",
               reviewed_at: 1.hour.ago)
      end

      let!(:negative_review) do
        create(:app_review, :negative,
               organization: organization,
               reviewable: apple_app,
               title: "Keeps crashing",
               body: "The app crashes whenever I open it.",
               reviewer_name: "Bob",
               reviewed_at: 2.hours.ago)
      end

      let!(:neutral_review) do
        create(:app_review, :neutral,
               organization: organization,
               reviewable: apple_app,
               title: "Average experience",
               body: "It works but nothing special.",
               reviewer_name: "Charlie",
               reviewed_at: 3.hours.ago)
      end

      let!(:android_review) do
        create(:app_review, :android,
               organization: organization,
               reviewable: android_app,
               rating: 4,
               title: "Nice Android app",
               body: "Works well on my Pixel.",
               reviewer_name: "Diana",
               reviewed_at: 30.minutes.ago)
      end

      it "shows the rating summary row with iOS rating" do
        get authenticated_root_path

        expect(response.body).to include("iOS")
        expect(response.body).to include("4.5")
      end

      it "shows the rating summary row with Android rating" do
        get authenticated_root_path

        expect(response.body).to include("Android")
        expect(response.body).to include("3.8")
      end

      it "shows review titles" do
        get authenticated_root_path

        expect(response.body).to include("Fantastic app")
        expect(response.body).to include("Keeps crashing")
      end

      it "shows review bodies" do
        get authenticated_root_path

        expect(response.body).to include("Love using this every day!")
      end

      it "shows sentiment badges" do
        get authenticated_root_path

        expect(response.body).to include("Positive")
        expect(response.body).to include("Negative")
      end

      it "shows All Reviews link" do
        get authenticated_root_path

        expect(response.body).to include("All Reviews")
      end

      it "limits to 5 recent reviews" do
        # Create more reviews to exceed the limit
        6.times do |i|
          create(:app_review,
                 organization: organization,
                 reviewable: apple_app,
                 rating: 4,
                 body: "Extra review batch #{i}",
                 reviewed_at: (i + 4).hours.ago)
        end

        get authenticated_root_path

        # We now have 10 reviews total (4 from let! + 6 created above).
        # Only the 5 most recent should appear. The oldest extras won't appear.
        # The 6 extras have reviewed_at from 4h to 9h ago.
        # Most recent 5 are: android_review (30min), positive (1h), negative (2h), neutral (3h), extra[0] (4h)
        expect(response.body).to include("Nice Android app")
        expect(response.body).to include("Fantastic app")
        # extra[5] at 9 hours ago should not be shown
        expect(response.body).not_to include("Extra review batch 5")
      end
    end
  end

  # ─── E. Expiring Assets ──────────────────────────────────────────────────────

  describe "expiring assets" do
    it "shows the Expiring Assets section heading" do
      get authenticated_root_path

      expect(response.body).to include("Expiring Assets")
    end

    context "with no expiring assets" do
      it "shows the healthy state" do
        get authenticated_root_path

        expect(response.body).to include("All assets healthy")
        expect(response.body).to include("No certificates, profiles, or keystores are expiring soon.")
      end
    end

    context "with an expiring certificate" do
      let!(:cert) do
        create(:apple_certificate,
               organization: organization,
               name: "iOS Distribution Cert",
               certificate_type: "IOS_DISTRIBUTION",
               platform: "IOS",
               expires_at: 10.days.from_now)
      end

      it "shows the expiring certificate with days remaining" do
        get authenticated_root_path

        expect(response.body).to include("iOS Distribution Cert")
        expect(response.body).to include("Certificate")
        expect(response.body).to include("Expires in 10 days")
      end
    end

    context "with an expiring provisioning profile" do
      let!(:profile) do
        create(:apple_provisioning_profile,
               organization: organization,
               name: "Ad Hoc Profile",
               platform: "IOS",
               expires_at: 5.days.from_now)
      end

      it "shows the expiring profile with days remaining" do
        get authenticated_root_path

        expect(response.body).to include("Ad Hoc Profile")
        expect(response.body).to include("Profile")
        expect(response.body).to include("Expires in 5 days")
      end
    end

    context "with an expiring keystore" do
      before do
        # mysigner-33 dropped the AR-encrypted columns (keystore_file,
        # keystore_password, key_password) from android_keystores. The
        # dashboard only reads `name` and `expires_at` for the expiring-
        # assets widget — the actual credential bytes live in
        # `keystore_file_envelope` etc. now and aren't relevant here.
        AndroidKeystore.insert!({
          organization_id: organization.id,
          name: "Release Keystore",
          expires_at: 15.days.from_now.to_date,
          active: true,
          created_at: Time.current,
          updated_at: Time.current
        })
      end

      it "shows the expiring keystore with days remaining" do
        get authenticated_root_path

        expect(response.body).to include("Release Keystore")
        expect(response.body).to include("Keystore")
        expect(response.body).to include("Expires in 15 days")
      end
    end

    context "with an asset expiring tomorrow" do
      let!(:cert) do
        create(:apple_certificate,
               organization: organization,
               name: "Urgent Cert",
               certificate_type: "IOS_DISTRIBUTION",
               platform: "IOS",
               expires_at: 1.day.from_now)
      end

      it "shows Expires tomorrow" do
        get authenticated_root_path

        expect(response.body).to include("Expires tomorrow")
      end
    end

    context "with an already expired asset" do
      let!(:cert) do
        create(:apple_certificate,
               organization: organization,
               name: "Dead Cert",
               certificate_type: "IOS_DISTRIBUTION",
               platform: "IOS",
               expires_at: 1.day.ago)
      end

      it "shows Expired" do
        get authenticated_root_path

        expect(response.body).to include("Expired")
      end
    end

    context "with multiple expiring assets sorted by urgency" do
      let!(:cert_far) do
        create(:apple_certificate,
               organization: organization,
               name: "Far Cert",
               certificate_type: "IOS_DISTRIBUTION",
               platform: "IOS",
               expires_at: 25.days.from_now)
      end

      let!(:profile_near) do
        create(:apple_provisioning_profile,
               organization: organization,
               name: "Near Profile",
               platform: "IOS",
               expires_at: 3.days.from_now)
      end

      it "shows the count badge and sorts nearest-expiry first" do
        get authenticated_root_path

        body = response.body
        expect(body).to include("Far Cert")
        expect(body).to include("Near Profile")
        # Near Profile should appear before Far Cert (sorted by days_remaining)
        expect(body.index("Near Profile")).to be < body.index("Far Cert")
      end
    end

    context "with assets that expire beyond 30 days" do
      let!(:cert) do
        create(:apple_certificate,
               organization: organization,
               name: "Distant Cert",
               certificate_type: "IOS_DISTRIBUTION",
               platform: "IOS",
               expires_at: 60.days.from_now)
      end

      it "does not show assets that expire beyond 30 days" do
        get authenticated_root_path

        expect(response.body).not_to include("Distant Cert")
        expect(response.body).to include("All assets healthy")
      end
    end
  end

  # ─── F. Quick Actions ─────────────────────────────────────────────────────────

  describe "quick actions" do
    it "shows core quick action buttons" do
      get authenticated_root_path

      expect(response.body).to include("New Release")
      expect(response.body).to include("Screenshots")
      expect(response.body).to include("Translate")
      expect(response.body).to include("Reviews")
    end

    context "without iOS credentials" do
      it "does not show iOS Apps link" do
        get authenticated_root_path

        expect(response.body).not_to include("iOS Apps")
      end
    end

    context "with iOS credentials" do
      before do
        AppStoreConnectCredential.create!(
          organization: organization,
          name: "ASC Key",
          key_id: "QA_KEY_123",
          issuer_id: "11111111-1111-1111-1111-111111111111",
          private_key: OpenSSL::PKey::EC.generate("prime256v1").to_pem,
          active: true
        )
      end

      it "shows iOS Apps link" do
        get authenticated_root_path

        expect(response.body).to include("iOS Apps")
      end
    end

    context "without Android credentials" do
      it "does not show Android Apps link" do
        get authenticated_root_path

        expect(response.body).not_to include("Android Apps")
      end
    end

    context "with Android credentials" do
      before do
        GooglePlayCredential.create!(
          organization: organization,
          name: "GP Cred",
          service_account_json: {
            type: "service_account",
            project_id: "test-project",
            private_key: SpecCredentialFixtures.pem,
            client_email: "test@test.iam.gserviceaccount.com",
            client_id: "123456789"
          }.to_json,
          active: true
        )
      end

      it "shows Android Apps link" do
        get authenticated_root_path

        expect(response.body).to include("Android Apps")
      end
    end
  end

  # ─── G. Screenshot Studio CTA ─────────────────────────────────────────────────

  describe "screenshot studio CTA" do
    context "with zero screenshot projects" do
      it "shows the first-time CTA with Create Project" do
        get authenticated_root_path

        expect(response.body).to include("Screenshot Studio")
        expect(response.body).to include("Create Project")
      end
    end

    context "with existing screenshot projects" do
      before do
        create(:screenshot_project, organization: organization, name: "Hero Screenshots")
      end

      it "shows the compact CTA with Open Studio and project count" do
        get authenticated_root_path

        expect(response.body).to include("Screenshot Studio")
        expect(response.body).to include("Open Studio")
        expect(response.body).to include("1 project")
      end
    end

    context "with multiple screenshot projects (pro plan)" do
      before do
        user.update!(plan_tier: :pro)
        create(:screenshot_project, organization: organization, name: "Screenshots A")
        create(:screenshot_project, organization: organization, name: "Screenshots B")
      end

      it "shows pluralized project count" do
        get authenticated_root_path

        expect(response.body).to include("2 projects")
      end
    end
  end

  # ─── H. Authentication ────────────────────────────────────────────────────────

  describe "authentication" do
    it "does not show the dashboard for unauthenticated users" do
      sign_out user
      get authenticated_root_path

      # Unauthenticated requests fall through to the landing page, not the dashboard
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Release Status")
      expect(response.body).not_to include("Expiring Assets")
    end
  end

  # ─── I. No Organization (Welcome Hero) ────────────────────────────────────────

  describe "no organization" do
    it "shows the welcome hero when user has no organization" do
      fresh_user = create(:user)
      sign_in fresh_user, scope: :user

      get authenticated_root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Welcome to")
      expect(response.body).to include("MySigner")
      expect(response.body).to include("Create Organization")
    end

    it "shows feature cards in the welcome hero" do
      fresh_user = create(:user)
      sign_in fresh_user, scope: :user

      get authenticated_root_path

      expect(response.body).to include("iOS Management")
      expect(response.body).to include("Android Ops")
      expect(response.body).to include("Organization First")
      expect(response.body).to include("CLI-First")
    end
  end

  # ─── J. Sync Buttons ─────────────────────────────────────────────────────────

  describe "sync buttons" do
    context "without any credentials" do
      it "does not show Sync iOS or Sync Android buttons" do
        get authenticated_root_path

        expect(response.body).not_to include("Sync iOS")
        expect(response.body).not_to include("Sync Android")
      end
    end

    context "with iOS credentials" do
      before do
        AppStoreConnectCredential.create!(
          organization: organization,
          name: "Sync ASC",
          key_id: "SYNC_KEY_1",
          issuer_id: "22222222-2222-2222-2222-222222222222",
          private_key: OpenSSL::PKey::EC.generate("prime256v1").to_pem,
          active: true
        )
      end

      it "shows the unified Sync button when iOS creds are active" do
        get authenticated_root_path

        # The unified "Sync" button now lives in the navbar (single source
        # of truth for sync state). It posts to sync_all_organization_path.
        expect(response.body).to include("navbar-sync-button")
        expect(response.body).to include(sync_all_organization_path(organization))
      end
    end

    context "with Android credentials" do
      before do
        GooglePlayCredential.create!(
          organization: organization,
          name: "Sync GP",
          service_account_json: {
            type: "service_account",
            project_id: "sync-project",
            private_key: SpecCredentialFixtures.pem(body: "sync"),
            client_email: "sync@test.iam.gserviceaccount.com",
            client_id: "987654321"
          }.to_json,
          active: true
        )
      end

      it "shows the unified Sync button when Android creds are active" do
        get authenticated_root_path

        expect(response.body).to include("navbar-sync-button")
        expect(response.body).to include(sync_all_organization_path(organization))
      end
    end

    context "with both iOS and Android credentials" do
      before do
        AppStoreConnectCredential.create!(
          organization: organization,
          name: "Both ASC",
          key_id: "BOTH_KEY_1",
          issuer_id: "33333333-3333-3333-3333-333333333333",
          private_key: OpenSSL::PKey::EC.generate("prime256v1").to_pem,
          active: true
        )
        GooglePlayCredential.create!(
          organization: organization,
          name: "Both GP",
          service_account_json: {
            type: "service_account",
            project_id: "both-project",
            private_key: SpecCredentialFixtures.pem(body: "both"),
            client_email: "both@test.iam.gserviceaccount.com",
            client_id: "111222333"
          }.to_json,
          active: true
        )
      end

      it "shows a single unified Sync button when both platforms are active" do
        get authenticated_root_path

        # We no longer render separate iOS / Android sync buttons — the
        # navbar's unified Sync button is the only one on the dashboard.
        body = response.body
        expect(body).to include("navbar-sync-button")
        expect(body).to include(sync_all_organization_path(organization))
        expect(body.scan("navbar-sync-button").size).to eq(1)
      end
    end
  end

  # ─── K. Edge Cases ────────────────────────────────────────────────────────────

  describe "edge cases" do
    describe "cross-organization isolation" do
      let(:other_user) { create(:user) }
      let(:other_org) { create(:organization, owner: other_user) }

      let!(:other_app) { create(:apple_app, organization: other_org, name: "OtherOrgApp", sku: "other-org-1") }
      let!(:other_asv) { create(:app_store_version, apple_app: other_app, organization: other_org, app_store_state: "READY_FOR_SALE", version_string: "9.0.0") }
      let!(:other_review) { create(:app_review, organization: other_org, reviewable: other_app, body: "Secret other org review", reviewed_at: 1.hour.ago) }

      it "does not show another organization's apps or reviews" do
        get authenticated_root_path

        expect(response.body).not_to include("OtherOrgApp")
        expect(response.body).not_to include("Secret other org review")
      end
    end

    describe "header stats summary" do
      let!(:apple_app) { create(:apple_app, organization: organization, name: "StatsApp", sku: "stats-ios-1") }
      let!(:asv) { create(:app_store_version, apple_app: apple_app, organization: organization, app_store_state: "READY_FOR_SALE", version_string: "1.0.0") }

      it "shows the live count in the stats row" do
        get authenticated_root_path

        expect(response.body).to include("Apps")
        expect(response.body).to include("1 live")
      end

      it "shows the downloads stat in the header" do
        create(:app_analytics_snapshot,
               organization: organization,
               snapshotable: apple_app,
               snapshot_date: 5.days.ago.to_date,
               total_downloads: 1234)

        get authenticated_root_path

        expect(response.body).to include("Downloads")
        expect(response.body).to include("1,234")
      end
    end

    describe "expiring assets header stat" do
      let!(:cert) do
        create(:apple_certificate,
               organization: organization,
               name: "Expiring For Stat",
               certificate_type: "IOS_DISTRIBUTION",
               platform: "IOS",
               expires_at: 7.days.from_now)
      end

      it "shows the expiring count in the header stats" do
        get authenticated_root_path

        expect(response.body).to include("Expiring")
        expect(response.body).to include("within 30 days")
      end
    end

    describe "rating snapshot trends" do
      let!(:apple_app) { create(:apple_app, organization: organization, sku: "trend-ios-1") }

      it "calculates a stable trend when there is only one snapshot" do
        create(:rating_snapshot,
               organization: organization,
               snapshotable: apple_app,
               snapshot_date: Date.current,
               average_rating: 4.0)

        get authenticated_root_path

        # With only one snapshot, no previous to compare to - just shows rating
        expect(response.body).to include("4.0")
      end
    end

    describe "all section headings are present" do
      it "renders all dashboard sections" do
        get authenticated_root_path

        expect(response.body).to include("Release Status")
        expect(response.body).to include("Analytics")
        expect(response.body).to include("Reviews &amp; Ratings")
        expect(response.body).to include("Expiring Assets")
        expect(response.body).to include("Screenshot Studio")
      end
    end

    describe "multiple iOS apps with explicit SKUs" do
      let!(:app1) { create(:apple_app, organization: organization, name: "App One", sku: "sku-one") }
      let!(:app2) { create(:apple_app, organization: organization, name: "App Two", sku: "sku-two") }
      let!(:asv1) { create(:app_store_version, apple_app: app1, organization: organization, app_store_state: "READY_FOR_SALE", version_string: "1.0.0") }
      let!(:asv2) { create(:app_store_version, apple_app: app2, organization: organization, app_store_state: "IN_REVIEW", version_string: "2.0.0") }

      it "shows both apps with their respective statuses" do
        get authenticated_root_path

        expect(response.body).to include("App One")
        expect(response.body).to include("App Two")
        expect(response.body).to include("Live")
        expect(response.body).to include("In Review")
      end
    end
  end
end
