require "rails_helper"

RSpec.describe "Releases", type: :request do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) { create(:apple_app, organization: organization) }
  let(:android_app) { create(:android_app, organization: organization) }
  let(:apple_release_id) { "apple_app_#{apple_app.id}" }
  let(:android_release_id) { "android_app_#{android_app.id}" }

  before do
    sign_in user, scope: :user
  end

  describe "GET /organizations/:organization_id/releases" do
    it "loads the unified releases index" do
      get organization_releases_path(organization)
      expect(response).to have_http_status(:ok)
    end

    it "redirects unauthenticated users" do
      sign_out user
      get organization_releases_path(organization)
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "GET /organizations/:organization_id/releases/:id" do
    it "loads the release detail page using apple_app_ID prefix" do
      get organization_release_path(organization, apple_release_id)
      expect(response).to have_http_status(:ok)
    end

    it "loads the release detail page using android_app_ID prefix" do
      get organization_release_path(organization, android_release_id)
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown app id" do
      get organization_release_path(organization, "apple_app_99999999")
      expect(response).to have_http_status(:not_found)
    end

    it "defaults to listing tab when no release note exists" do
      get organization_release_path(organization, apple_release_id)
      expect(response).to have_http_status(:ok)
    end

    it "respects the tab query param" do
      get organization_release_path(organization, apple_release_id, tab: "build")
      expect(response).to have_http_status(:ok)
    end

    it "creates an AppRelease lazily on first view" do
      expect {
        get organization_release_path(organization, apple_release_id)
      }.to change(AppRelease, :count).by(1)
    end
  end

  describe "GET /organizations/:organization_id/releases/:id/sync_status" do
    let!(:listing) { create(:store_listing, organization: organization, listable: apple_app, locale: "en-US") }

    it "returns JSON status payload" do
      get sync_status_organization_release_path(organization, apple_release_id), as: :json
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data).to include("sync_status", "push_status", "locale_count")
    end

    it "returns unknown when no listings exist for the app" do
      listing.destroy
      get sync_status_organization_release_path(organization, apple_release_id), as: :json
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["sync_status"]).to eq("unknown")
    end
  end

  describe "POST /organizations/:organization_id/releases/:id/sync" do
    it "enqueues a sync job and redirects" do
      expect {
        post sync_organization_release_path(organization, apple_release_id)
      }.to have_enqueued_job(StoreListingSyncJob)
      expect(response).to redirect_to(organization_release_path(organization, apple_release_id))
    end
  end

  describe "POST /organizations/:organization_id/releases/:id/push" do
    let!(:listing) { create(:store_listing, organization: organization, listable: apple_app, locale: "en-US") }

    context "when user has push entitlement" do
      before { user.update!(plan_tier: :pro) }

      it "enqueues a push job" do
        expect {
          post push_organization_release_path(organization, apple_release_id)
        }.to have_enqueued_job(StoreListingPushJob)
      end

      it "redirects with success notice" do
        post push_organization_release_path(organization, apple_release_id)
        expect(response).to redirect_to(organization_release_path(organization, apple_release_id))
      end

      context "when there's a pending-review release note (team org)" do
        before do
          # Activate review workflow by adding a second member (needs team plan for 2+ seats)
          user.update!(plan_tier: :team)
          organization.memberships.create!(user: create(:user), role: :developer)
          create(:release_note, :pending_review, organization: organization, listable: apple_app, version_string: "1.0.0")
        end

        it "blocks the push and redirects with alert" do
          expect {
            post push_organization_release_path(organization, apple_release_id)
          }.not_to have_enqueued_job(StoreListingPushJob)
          expect(flash[:alert]).to match(/awaiting approval/i)
        end
      end
    end

    context "when user lacks push entitlement (free plan)" do
      it "shows upgrade prompt and does not enqueue" do
        expect {
          post push_organization_release_path(organization, apple_release_id)
        }.not_to have_enqueued_job(StoreListingPushJob)
      end
    end
  end

  describe "POST /organizations/:organization_id/releases/:id/push (auto-detected blockers)" do
    let!(:listing) { create(:store_listing, organization: organization, listable: apple_app, locale: "en-US") }
    let!(:checklist) { create(:release_checklist, organization: organization, listable: apple_app, version_string: "1.0.0") }

    before { user.update!(plan_tier: :pro) }

    it "blocks push when a required error-severity auto item exists" do
      blocking_item = {
        "key" => "auto_ios_rejected",
        "label" => "Apple rejected version 1.0.0",
        "detail" => "blah",
        "severity" => "error",
        "required" => true,
        "auto_detected" => true,
        "source" => "app_store_connect",
        "action_url" => nil,
        "category" => "issue"
      }
      allow_any_instance_of(ReleaseChecklist).to receive(:auto_detected_items).and_return([ blocking_item ])

      expect {
        post push_organization_release_path(organization, "apple_app_#{apple_app.id}")
      }.not_to have_enqueued_job(StoreListingPushJob)

      expect(response).to redirect_to(
        organization_release_path(organization, "apple_app_#{apple_app.id}", tab: "checklist")
      )
      expect(flash[:alert]).to match(/required issue/i)
    end

    it "does NOT block push when auto items are warnings or info" do
      warning_item = {
        "key" => "auto_warn",
        "label" => "Heads up",
        "detail" => "blah",
        "severity" => "warning",
        "required" => true,
        "auto_detected" => true,
        "source" => "local_check",
        "action_url" => nil,
        "category" => "issue"
      }
      allow_any_instance_of(ReleaseChecklist).to receive(:auto_detected_items).and_return([ warning_item ])

      expect {
        post push_organization_release_path(organization, "apple_app_#{apple_app.id}")
      }.to have_enqueued_job(StoreListingPushJob)
    end

    it "does NOT block push when there are no auto items" do
      allow_any_instance_of(ReleaseChecklist).to receive(:auto_detected_items).and_return([])

      expect {
        post push_organization_release_path(organization, "apple_app_#{apple_app.id}")
      }.to have_enqueued_job(StoreListingPushJob)
    end

    it "skips guard when no checklist exists for the app" do
      checklist.destroy
      allow_any_instance_of(ReleaseChecklist).to receive(:auto_detected_items).and_return([])

      expect {
        post push_organization_release_path(organization, "apple_app_#{apple_app.id}")
      }.to have_enqueued_job(StoreListingPushJob)
    end
  end

  describe "PATCH /organizations/:organization_id/releases/:id (update listing)" do
    let!(:listing) {
      create(:store_listing, organization: organization, listable: apple_app, locale: "en-US",
             app_name: "Old Name")
    }

    it "updates store listing fields for the current locale" do
      patch organization_release_path(organization, apple_release_id, locale: "en-US"),
        params: { store_listing: { app_name: "New Name", description: "Updated desc" } }

      expect(response).to redirect_to(
        organization_release_path(organization, apple_release_id, tab: "listing", locale: "en-US")
      )
      expect(listing.reload.app_name).to eq("New Name")
    end

    it "does not allow whats_new to be updated via the listing form" do
      patch organization_release_path(organization, apple_release_id, locale: "en-US"),
        params: { store_listing: { whats_new: "Hacked release notes" } }

      expect(listing.reload.whats_new).not_to eq("Hacked release notes")
    end
  end

  describe "POST /organizations/:organization_id/releases/:id/submit_to_store" do
    let!(:credential) do
      AppStoreConnectCredential.create!(
        organization: organization,
        name: "Test",
        key_id: "ABC12345XY",
        issuer_id: "DEF456789-1234567890-ABC",
        private_key: "-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----",
        active: true
      )
    end
    let!(:apple_build) { create(:apple_build, apple_app: apple_app, organization: organization) }
    let!(:version) do
      create(:app_store_version,
             apple_app: apple_app,
             organization: organization,
             version_string: "1.0.0",
             app_store_state: "PREPARE_FOR_SUBMISSION",
             apple_build: apple_build)
    end

    it "enqueues AppStoreSubmitJob and marks the version as submitting" do
      expect {
        post submit_to_store_organization_release_path(organization, apple_release_id)
      }.to have_enqueued_job(AppStoreSubmitJob).with(
        hash_including(
          organization_id: organization.id,
          app_store_version_id: version.id,
          release_type: "AFTER_APPROVAL"
        )
      )

      expect(version.reload.submission_status).to eq("submitting")
      expect(response).to redirect_to(
        organization_release_path(organization, apple_release_id, tab: "submission")
      )
      expect(flash[:notice]).to match(/Submitting v1\.0\.0/)
    end

    it "refuses to submit Android apps" do
      expect {
        post submit_to_store_organization_release_path(organization, android_release_id)
      }.not_to have_enqueued_job(AppStoreSubmitJob)
      expect(flash[:alert]).to match(/only supported for iOS/)
    end

    it "refuses when no active credential exists" do
      credential.update!(active: false)

      expect {
        post submit_to_store_organization_release_path(organization, apple_release_id)
      }.not_to have_enqueued_job(AppStoreSubmitJob)
      expect(flash[:alert]).to match(/No active App Store Connect credential/)
    end

    it "refuses when version is in a non-submittable state" do
      version.update!(app_store_state: "WAITING_FOR_REVIEW")

      expect {
        post submit_to_store_organization_release_path(organization, apple_release_id)
      }.not_to have_enqueued_job(AppStoreSubmitJob)
      expect(flash[:alert]).to match(/can't be submitted/)
    end

    it "refuses when a submission is already in progress" do
      version.update!(submission_status: "submitting")

      expect {
        post submit_to_store_organization_release_path(organization, apple_release_id)
      }.not_to have_enqueued_job(AppStoreSubmitJob)
      expect(flash[:alert]).to match(/already in progress/)
    end

    it "refuses when no build is attached" do
      version.update!(apple_build: nil)

      expect {
        post submit_to_store_organization_release_path(organization, apple_release_id)
      }.not_to have_enqueued_job(AppStoreSubmitJob)
      expect(flash[:alert]).to match(/No build attached/)
    end

    it "refuses SCHEDULED release without a date" do
      expect {
        post submit_to_store_organization_release_path(organization, apple_release_id),
             params: { release_type: "SCHEDULED" }
      }.not_to have_enqueued_job(AppStoreSubmitJob)
      expect(flash[:alert]).to match(/at least 1 hour in the future/)
    end

    it "refuses SCHEDULED release less than 1 hour in the future" do
      expect {
        post submit_to_store_organization_release_path(organization, apple_release_id),
             params: { release_type: "SCHEDULED", earliest_release_date: 30.minutes.from_now.iso8601 }
      }.not_to have_enqueued_job(AppStoreSubmitJob)
      expect(flash[:alert]).to match(/at least 1 hour in the future/)
    end

    it "accepts SCHEDULED release with a valid future date" do
      future = 2.hours.from_now

      expect {
        post submit_to_store_organization_release_path(organization, apple_release_id),
             params: { release_type: "SCHEDULED", earliest_release_date: future.iso8601 }
      }.to have_enqueued_job(AppStoreSubmitJob).with(
        hash_including(release_type: "SCHEDULED")
      )
    end

    it "blocks submission when a required error-severity auto item exists" do
      create(:release_checklist, organization: organization, listable: apple_app, version_string: "1.0.0")
      blocking_item = {
        "key" => "auto_ios_rejected",
        "label" => "Apple rejected version 1.0.0",
        "detail" => "blah",
        "severity" => "error",
        "required" => true,
        "auto_detected" => true,
        "source" => "app_store_connect"
      }
      allow_any_instance_of(ReleaseChecklist).to receive(:auto_detected_items).and_return([ blocking_item ])

      expect {
        post submit_to_store_organization_release_path(organization, apple_release_id)
      }.not_to have_enqueued_job(AppStoreSubmitJob)

      expect(response).to redirect_to(
        organization_release_path(organization, apple_release_id, tab: "checklist")
      )
      expect(flash[:alert]).to match(/required issue/i)
    end
  end

  describe "POST /organizations/:organization_id/releases/:id/refresh_validation_errors" do
    let!(:credential) do
      AppStoreConnectCredential.create!(
        organization: organization,
        name: "Test",
        key_id: "ABC12345XY",
        issuer_id: "DEF456789-1234567890-ABC",
        private_key: "-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----",
        active: true
      )
    end
    let!(:version) do
      create(:app_store_version,
             apple_app: apple_app,
             organization: organization,
             version_string: "1.0.0",
             app_store_state: "PREPARE_FOR_SUBMISSION")
    end

    let(:mock_client) { instance_double(AppStoreConnect::Client) }
    let(:mock_versions_service) { instance_double(AppStoreConnect::Versions) }

    before do
      allow(AppStoreConnect::Client).to receive(:new).and_return(mock_client)
      allow(AppStoreConnect::Versions).to receive(:new).and_return(mock_versions_service)
    end

    it "stores refreshed validation errors on the version" do
      allow(mock_versions_service).to receive(:validation_errors)
        .with(version_id: version.version_id)
        .and_return([ "MISSING_SCREENSHOTS: iPhone 6.7\" screenshots are required" ])

      post refresh_validation_errors_organization_release_path(organization, apple_release_id)

      expect(version.reload.issues).to be_an(Array)
      expect(version.issues.size).to eq(1)
      expect(version.issues.first["detail"]).to include("MISSING_SCREENSHOTS")
      expect(flash[:notice]).to match(/1 issue/)
    end

    it "reports 'no issues' when Apple returns an empty list" do
      allow(mock_versions_service).to receive(:validation_errors).and_return([])

      post refresh_validation_errors_organization_release_path(organization, apple_release_id)

      expect(flash[:notice]).to match(/No issues/)
    end
  end

  describe "POST /organizations/:organization_id/releases/:id/release_notes (create release note)" do
    it "creates a release note for the current app" do
      expect {
        post create_release_note_organization_release_path(organization, apple_release_id),
          params: { release_note: { version_string: "2.5.0", locale: "en-US" } }
      }.to change(ReleaseNote, :count).by(1)

      note = ReleaseNote.last
      expect(note.listable).to eq(apple_app)
      expect(note.version_string).to eq("2.5.0")
      expect(note.created_by).to eq(user)
    end
  end

  describe "PATCH /organizations/:organization_id/releases/:id/release_notes/:note_id" do
    let!(:note) { create(:release_note, organization: organization, listable: apple_app, version_string: "1.0.0") }

    it "updates an existing release note" do
      patch update_release_note_organization_release_path(organization, apple_release_id, note_id: note.id),
        params: { release_note: { rendered_text: "Updated text" } }

      expect(note.reload.rendered_text).to eq("Updated text")
    end
  end

  describe "POST /organizations/:organization_id/releases/:id/add_locale" do
    let!(:listing) { create(:store_listing, organization: organization, listable: apple_app, locale: "en-US") }

    before { user.update!(plan_tier: :pro) }

    it "creates a new locale listing" do
      expect {
        post add_locale_organization_release_path(organization, apple_release_id), params: { locale: "de-DE" }
      }.to change { apple_app.store_listings.count }.by(1)
    end
  end

  describe "POST /organizations/:organization_id/releases/:id/create_listing" do
    it "creates an initial store listing for an app with none" do
      expect {
        post create_listing_organization_release_path(organization, apple_release_id)
      }.to change { apple_app.store_listings.count }.by(1)
    end
  end

  describe "authentication" do
    it "redirects unauthenticated users" do
      sign_out user
      get organization_releases_path(organization)
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "authorization" do
    let(:non_member) { create(:user) }

    before { sign_in non_member, scope: :user }

    # Non-members 404 instead of redirect/forbidden: set_org now scopes to
    # current_user.organizations, so an existing-but-not-mine id is
    # indistinguishable from a non-existent id (closes the enumeration
    # oracle). See OrganizationsController#set_organization.
    it "denies index to non-members" do
      get organization_releases_path(organization)
      expect(response).to have_http_status(:not_found)
    end

    it "denies show to non-members" do
      get organization_release_path(organization, apple_release_id)
      expect(response).to have_http_status(:not_found)
    end

    it "denies sync_status to non-members (JSON)" do
      get sync_status_organization_release_path(organization, apple_release_id), as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
