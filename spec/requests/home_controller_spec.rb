require "rails_helper"

RSpec.describe "HomeController", type: :request do
  let(:user) { create(:user, plan_tier: :free) }
  let(:organization) { create(:organization, owner: user) }

  before do
    Rails.cache.clear
    sign_in user, scope: :user
    post switch_organization_path(organization)
  end

  it "keeps stale dashboard sync enabled for free plans" do
    expect(organization.scheduled_sync_enabled?).to be(true)
    expect(organization.entitlements.stale_dashboard_sync_enabled?).to be(true)

    AppStoreConnectCredential.create!(
      organization: organization,
      name: "Primary ASC",
      key_id: "FREE1234",
      issuer_id: "11111111-1111-1111-1111-111111111111",
      private_key: OpenSSL::PKey::EC.generate("prime256v1").to_pem,
      team_id: "TEAMFREE1",
      active: true,
      last_synced_at: 5.hours.ago
    )
    GooglePlayCredential.create!(
      organization: organization,
      name: "Primary GP",
      service_account_json: {
        type: "service_account",
        project_id: "free-project",
        private_key: "-----BEGIN PRIVATE KEY-----\nfree\n-----END PRIVATE KEY-----\n",
        client_email: "free@example.com",
        client_id: "123"
      }.to_json,
      active: true,
      last_synced_at: 5.hours.ago
    )

    expect {
      get authenticated_root_path
    }.to have_enqueued_job(AppStoreConnectSyncJob).with(organization.id)
      .and have_enqueued_job(GooglePlaySyncJob).with(organization.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Screenshot Studio")
    expect(response.body).to include("Create Project")
  end

  it "falls back to the first accessible organization when the session organization becomes blocked" do
    user.update!(plan_tier: :team)
    organizations = Array.new(5) { |index| create(:organization, owner: user, name: "Org #{index + 1}", created_at: (5 - index).days.ago) }

    post switch_organization_path(organizations.last)
    user.update!(plan_tier: :pro)
    Pricing::PlanEnforcer.new(user).apply!

    get authenticated_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Everything #{organizations.first.name} needs")
    expect(response.body).not_to include("Everything #{organizations.last.name} needs")
    expect(user.reload.last_organization_id).to eq(organizations.first.id)
  end

  describe "sync-error-alerts section" do
    # Regression: the navbar's unified-Sync button uses Sync::StatusAggregator
    # to drive its polling toast; on partial / error completion the toast
    # links to "/#sync-error-alerts" so the user can read the actual error
    # message. Previously the home dashboard only rendered cards for
    # iOS-credential and Android-credential failures, so a failed
    # keyword-rank / reviews / analytics / cpp job had no card AND the
    # section element itself didn't render -- making the "See details"
    # link a silent no-op.
    it "renders an error card for a failed keyword-rank job and exposes the anchor" do
      OrgSyncRun.create!(
        organization: organization,
        job_name: "keywords_rank",
        status: "error",
        started_at: 10.minutes.ago,
        finished_at: 9.minutes.ago,
        error_message: "Rate limited by Apple Search Ads"
      )

      get authenticated_root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="sync-error-alerts"')
      expect(response.body).to include("Keyword rankings sync failed")
      expect(response.body).to include("Rate limited by Apple Search Ads")
    end

    it "shows a stranded-worker hint and a Retry button when an active platform credential exists" do
      AppStoreConnectCredential.create!(
        organization: organization,
        name: "Primary ASC",
        key_id: "RETRY1234",
        issuer_id: "11111111-1111-1111-1111-111111111111",
        private_key: OpenSSL::PKey::EC.generate("prime256v1").to_pem,
        team_id: "TEAMRT001",
        active: true
      )
      OrgSyncRun.create!(
        organization: organization,
        job_name: "keywords_rank",
        status: "error",
        started_at: 30.minutes.ago,
        finished_at: 25.minutes.ago,
        error_message: "Sync did not complete (worker exited before finishing)"
      )

      get authenticated_root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("worker died mid-run")
      expect(response.body).to include("Retry")
      expect(response.body).to include(sync_all_organization_path(organization))
    end

    it "classifies a rate-limit error message into the throttling hint" do
      OrgSyncRun.create!(
        organization: organization,
        job_name: "reviews",
        status: "error",
        started_at: 10.minutes.ago,
        finished_at: 9.minutes.ago,
        error_message: "HTTP 429 rate limit exceeded"
      )

      get authenticated_root_path

      expect(response.body).to include("Throttled by the upstream API")
    end

    it "classifies a credential error message into the credentials-update hint" do
      OrgSyncRun.create!(
        organization: organization,
        job_name: "analytics",
        status: "error",
        started_at: 10.minutes.ago,
        finished_at: 9.minutes.ago,
        error_message: "Apple returned 401 Unauthorized"
      )

      get authenticated_root_path

      expect(response.body).to include("credentials look invalid or expired")
    end

    it "exposes a Dismiss form posting DELETE to the per-job sync_run endpoint" do
      OrgSyncRun.create!(
        organization: organization,
        job_name: "keywords_rank",
        status: "error",
        started_at: 10.minutes.ago,
        finished_at: 9.minutes.ago,
        error_message: "Sync did not complete (worker exited before finishing)"
      )

      get authenticated_root_path

      expect(response.body).to include("Dismiss")
      expect(response.body).to include(organization_sync_run_path(organization, job_name: "keywords_rank"))
    end

    it "does not render the anchor when no sync errors exist" do
      get authenticated_root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('id="sync-error-alerts"')
    end
  end

  it "prefers the oldest accessible owned organization over shared organizations after a downgrade" do
    user.update!(plan_tier: :team)
    shared_owner = create(:user, :team_plan)
    shared_organization = create(:organization, owner: shared_owner, name: "Shared Org", created_at: 10.days.ago)
    create(:membership, organization: shared_organization, user: user, role: :developer)
    organizations = Array.new(5) { |index| create(:organization, owner: user, name: "Org #{index + 1}", created_at: (5 - index).days.ago) }

    post switch_organization_path(organizations.last)
    user.update!(plan_tier: :pro)
    Pricing::PlanEnforcer.new(user).apply!

    get authenticated_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Everything #{organizations.first.name} needs")
    expect(response.body).not_to include("Everything Shared Org needs")
    expect(user.reload.last_organization_id).to eq(organizations.first.id)
  end
end
