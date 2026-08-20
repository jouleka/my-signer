require "rails_helper"

RSpec.describe "OnboardingController", type: :request do
  let(:user) { create(:user, :needs_onboarding) }

  # Helper: sign in and set org in session without triggering the auto-complete
  # side-effect that `switch_organization_path` causes.
  def sign_in_with_org(user, organization, onboarding_step:)
    sign_in user, scope: :user
    # Switch sets the session org but also auto-completes onboarding,
    # so we reset the onboarding state right after.
    post switch_organization_path(organization)
    user.update_columns(onboarding_completed_at: nil, onboarding_step: onboarding_step)
  end

  # ── Unauthenticated ────────────────────────────────────────────────

  describe "unauthenticated" do
    it "redirects to sign-in" do
      get onboarding_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  # ── Redirect logic ─────────────────────────────────────────────────

  describe "onboarding redirect" do
    before { sign_in user, scope: :user }

    it "redirects new users with no orgs to onboarding from the homepage" do
      get authenticated_root_path
      expect(response).to redirect_to(onboarding_path)
    end

    it "auto-completes onboarding for existing users who already have orgs" do
      create(:organization, owner: user)
      expect(user.onboarding_completed_at).to be_nil

      get authenticated_root_path

      expect(user.reload.onboarding_completed_at).to be_present
      expect(response).to have_http_status(:ok)
    end

    it "does not redirect users who have completed onboarding" do
      create(:organization, owner: user)
      user.update_columns(onboarding_completed_at: Time.current)

      get authenticated_root_path
      expect(response).to have_http_status(:ok)
    end

    it "redirects completed users away from onboarding back to dashboard" do
      user.update_columns(onboarding_completed_at: Time.current)

      get onboarding_path
      expect(response).to redirect_to(authenticated_root_path)
    end

    it "does not redirect API requests to onboarding" do
      get "/api/v1/status"
      expect(response).not_to redirect_to(onboarding_path)
    end
  end

  # ── after_sign_in_path_for ─────────────────────────────────────────

  describe "after sign-in redirect" do
    it "sends new users to onboarding after sign-in" do
      post user_session_path, params: {
        user: { email: user.email, password: "Password123!@#" }
      }
      expect(response).to redirect_to(onboarding_path)
    end

    it "sends existing users with orgs to the dashboard after sign-in" do
      org = create(:organization, owner: user)
      user.update_columns(onboarding_completed_at: Time.current, last_organization_id: org.id)

      post user_session_path, params: {
        user: { email: user.email, password: "Password123!@#" }
      }
      expect(response).to redirect_to(authenticated_root_path)
    end
  end

  # ── Step 1: Organization ───────────────────────────────────────────

  describe "GET /onboarding (organization step)" do
    before { sign_in user, scope: :user }

    it "renders the create organization step for users with no orgs" do
      get onboarding_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Your")
      expect(response.body).to include("workspace")
      expect(response.body).to include("What platforms do you ship to?")
    end

    it "shows full-screen layout without sidebar or navbar" do
      get onboarding_path
      doc = Nokogiri::HTML(response.body)

      expect(doc.at_css("#app-drawer")).to be_nil
      expect(response.body).to include("data-controller=\"onboarding\"")
    end

    it "auto-fills org name from email domain" do
      user.update_columns(email: "dev@acmecorp.com")
      get onboarding_path
      expect(response.body).to include("Acmecorp")
    end
  end

  describe "POST /onboarding/organization" do
    before { sign_in user, scope: :user }

    it "creates an organization and advances to CLI step" do
      expect {
        post onboarding_create_organization_path, params: {
          organization: { name: "My Company" },
          platform: "ios"
        }
      }.to change(Organization, :count).by(1)

      expect(response).to redirect_to(onboarding_path(step: "cli"))

      org = Organization.last
      expect(org.name).to eq("My Company")
      expect(org.owner).to eq(user)

      user.reload
      expect(user.onboarding_step).to eq(1)
      expect(user.onboarding_platform).to eq("ios")
    end

    it "saves platform preference as 'both' by default" do
      post onboarding_create_organization_path, params: {
        organization: { name: "My Org" }
      }
      expect(user.reload.onboarding_platform).to eq("both")
    end

    it "creates an admin membership for the owner" do
      post onboarding_create_organization_path, params: {
        organization: { name: "My Org" },
        platform: "android"
      }

      org = Organization.last
      membership = org.memberships.find_by(user: user)
      expect(membership).to be_present
      expect(membership.role).to eq("admin")
    end

    it "re-renders with errors when name is blank" do
      expect {
        post onboarding_create_organization_path, params: {
          organization: { name: "" },
          platform: "both"
        }
      }.not_to change(Organization, :count)

      expect(response).to have_http_status(:unprocessable_content)
      # The redesigned organization step uses "Your workspace" as the H1;
      # the form action ("Create organization & continue") is also unique
      # to this step and confirms we re-rendered the same template.
      expect(response.body).to include("Create organization &amp; continue").or include("Create organization & continue")
    end
  end

  # ── Step 2: CLI ────────────────────────────────────────────────────

  describe "GET /onboarding?step=cli" do
    let(:organization) { create(:organization, owner: user) }

    before { sign_in_with_org(user, organization, onboarding_step: 1) }

    it "renders the CLI install step" do
      get onboarding_path(step: "cli")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Install the MySigner CLI")
      expect(response.body).to include("gem install mysigner")
    end

    it "shows Ruby install help section" do
      get onboarding_path(step: "cli")
      expect(response.body).to include("brew install ruby")
      expect(response.body).to include("sudo apt install ruby-full")
      # Windows guidance now points at RubyInstaller (the redesigned step
      # dropped the winget alternative — `gem install` requires Ruby + dev
      # toolchain, which RubyInstaller bundles).
      expect(response.body).to include("RubyInstaller")
    end
  end

  # ── Step 3: Token ──────────────────────────────────────────────────

  describe "GET /onboarding?step=token" do
    let(:organization) { create(:organization, owner: user) }

    before { sign_in_with_org(user, organization, onboarding_step: 2) }

    it "renders the token generation form" do
      get onboarding_path(step: "token")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Generate an")
      expect(response.body).to include("API token")
      expect(response.body).to include("Permission level")
    end
  end

  describe "POST /onboarding/token" do
    let(:organization) { create(:organization, owner: user) }

    before { sign_in_with_org(user, organization, onboarding_step: 2) }

    it "creates an API token and renders the token reveal page" do
      expect {
        post onboarding_create_token_path, params: {
          api_token: { name: "My CLI Token", scope_level: "admin" }
        }
      }.to change(ApiToken, :count).by(1)

      expect(response).to have_http_status(:ok)
      # The redesigned reveal page leads with "Copy this once, then move on"
      # and the warn strip "Save this token — shown only once". Either is
      # unique to the token-reveal step.
      expect(response.body).to include("Save this token")
      expect(response.body).to include("Copy this")

      token = ApiToken.last
      expect(token.name).to eq("My CLI Token")
      expect(token.scopes).to eq("read,write,admin")
      expect(token.organization).to eq(organization)
      expect(token.user).to eq(user)
      expect(token.expires_at).to be_nil

      expect(user.reload.onboarding_step).to eq(3)
    end

    it "creates a token with default name when none provided" do
      post onboarding_create_token_path, params: {
        api_token: { scope_level: "admin" }
      }
      expect(ApiToken.last.name).to eq("CLI Token (Onboarding)")
    end

    it "shows the user's email in the CLI login walkthrough" do
      post onboarding_create_token_path, params: {
        api_token: { name: "Token", scope_level: "read" }
      }

      expect(response.body).to include(user.email)
      expect(response.body).to include("mysigner login")
    end

    it "enqueues the token creation notification job" do
      expect {
        post onboarding_create_token_path, params: {
          api_token: { name: "Token", scope_level: "admin" }
        }
      }.to have_enqueued_job(ApiTokenCreatedNotificationJob)
    end
  end

  # ── Step 4: Connect ────────────────────────────────────────────────

  describe "GET /onboarding?step=connect" do
    let(:organization) { create(:organization, owner: user) }

    before do
      user.update_columns(onboarding_platform: "both")
      sign_in_with_org(user, organization, onboarding_step: 3)
    end

    it "renders the connect step with both platform cards" do
      get onboarding_path(step: "connect")
      expect(response).to have_http_status(:ok)
      # The redesigned step uses "Wire up signing credentials" as the H1.
      expect(response.body).to include("Wire up")
      expect(response.body).to include("signing credentials")
      expect(response.body).to include("App Store Connect")
      expect(response.body).to include("Google Play Console")
    end

    it "shows only iOS card when platform is ios" do
      user.update_columns(onboarding_platform: "ios")
      get onboarding_path(step: "connect")

      expect(response.body).to include("App Store Connect")
      expect(response.body).not_to include("Google Play Console")
    end

    it "shows only Android card when platform is android" do
      user.update_columns(onboarding_platform: "android")
      get onboarding_path(step: "connect")

      # The global layout has the ASC credential modal, so we check the onboarding content area
      doc = Nokogiri::HTML(response.body)
      onboarding_content = doc.at_css("[data-onboarding-content]").to_s

      expect(onboarding_content).not_to include("App Store Connect")
      expect(onboarding_content).to include("Google Play Console")
    end

    it "shows Connected badge when iOS credentials exist" do
      AppStoreConnectCredential.create!(
        organization: organization,
        name: "ASC Key",
        key_id: "TEST1234",
        issuer_id: "11111111-1111-1111-1111-111111111111",
        private_key: OpenSSL::PKey::EC.generate("prime256v1").to_pem,
        team_id: "TEAM1",
        active: true
      )

      get onboarding_path(step: "connect")
      expect(response.body).to include("Connected")
    end

    it "shows Finish setup button when all selected platforms are connected" do
      # Force iOS-only so a single ASC credential satisfies "all selected
      # platforms connected" — the redesigned step only promotes "Finish
      # setup" to the primary CTA when every platform the user said they
      # ship to has a credential. Under platform="both", an iOS-only
      # credential lands in the partial-connected branch ("Skip remaining
      # & finish") instead.
      user.update_columns(onboarding_platform: "ios")
      AppStoreConnectCredential.create!(
        organization: organization,
        name: "ASC Key",
        key_id: "TEST1234",
        issuer_id: "11111111-1111-1111-1111-111111111111",
        private_key: OpenSSL::PKey::EC.generate("prime256v1").to_pem,
        team_id: "TEAM1",
        active: true
      )

      get onboarding_path(step: "connect")
      expect(response.body).to include("Finish setup")
    end

    it "shows skip option when no credentials added" do
      get onboarding_path(step: "connect")
      expect(response.body).to include("I'll add credentials later")
    end
  end

  # ── Step 5: Complete ───────────────────────────────────────────────

  describe "GET /onboarding?step=complete" do
    let(:organization) { create(:organization, owner: user) }

    before do
      user.update_columns(onboarding_platform: "both")
      sign_in_with_org(user, organization, onboarding_step: 4)
    end

    it "renders the celebration page and marks onboarding complete" do
      get onboarding_path(step: "complete")
      expect(response).to have_http_status(:ok)
      # The redesigned celebration step uses "You're all set." as the lead
      # and "Open dashboard" as the primary CTA.
      expect(response.body).to include("all set")
      expect(response.body).to include("Open dashboard")

      expect(user.reload.onboarding_completed_at).to be_present
    end

    # The redesigned celebration step shows BOTH the iOS and Android ship
    # commands unconditionally — the editorial layout is fixed regardless
    # of the user's onboarding_platform choice. These three tests pin
    # that behavior so a future regression that hides the wrong terminal
    # block (or adds back a platform-specific gate) gets caught.
    it "shows iOS ship command regardless of platform setting" do
      user.update_columns(onboarding_platform: "ios")
      get onboarding_path(step: "complete")
      expect(response.body).to include("mysigner ship testflight")
    end

    it "shows Android ship command regardless of platform setting" do
      user.update_columns(onboarding_platform: "android")
      get onboarding_path(step: "complete")
      expect(response.body).to include("mysigner ship internal")
    end

    it "shows both platform commands when platform is both" do
      get onboarding_path(step: "complete")
      expect(response.body).to include("mysigner ship testflight")
      expect(response.body).to include("mysigner ship internal")
    end
  end

  # ── Advance ────────────────────────────────────────────────────────

  describe "POST /onboarding/advance" do
    let(:organization) { create(:organization, owner: user) }

    before { sign_in_with_org(user, organization, onboarding_step: 1) }

    it "advances the user to the specified step" do
      post onboarding_advance_path(step: "token")
      expect(user.reload.onboarding_step).to eq(2)
      expect(response).to redirect_to(onboarding_path(step: "token"))
    end

    it "redirects to onboarding root for invalid steps" do
      post onboarding_advance_path(step: "nonexistent")
      expect(response).to redirect_to(onboarding_path)
    end
  end

  # ── Skip ───────────────────────────────────────────────────────────

  describe "POST /onboarding/skip" do
    before { sign_in user, scope: :user }

    it "marks onboarding complete and redirects to dashboard" do
      post onboarding_skip_path
      expect(response).to redirect_to(authenticated_root_path)
      expect(user.reload.onboarding_completed_at).to be_present
    end
  end

  # ── Credential redirect during onboarding ──────────────────────────

  describe "credential redirect during onboarding" do
    let(:organization) { create(:organization, owner: user) }

    before do
      user.update_columns(onboarding_platform: "both")
      sign_in_with_org(user, organization, onboarding_step: 3)
    end

    it "redirects back to onboarding connect step after adding ASC credential" do
      # Stub the Apple credential validator since it calls the real API
      validation_result = double(team_id: "TEAMTEST1")
      validator_instance = instance_double(AppStoreConnect::CredentialValidator, validate!: validation_result)
      allow(AppStoreConnect::CredentialValidator).to receive(:new).and_return(validator_instance)

      post organization_app_store_connect_credentials_path(organization), params: {
        app_store_connect_credential: {
          name: "Test Key",
          key_id: "ABC1234567",
          issuer_id: "11111111-1111-1111-1111-111111111111",
          private_key: OpenSSL::PKey::EC.generate("prime256v1").to_pem
        }
      }

      expect(response).to redirect_to(onboarding_path(step: "connect"))
    end

    it "redirects to org page after adding credential when onboarding is complete" do
      user.update_columns(onboarding_completed_at: Time.current)
      # `after_credential_path` now also checks
      # `onboarding_has_pending_platform?` and bounces the user back to
      # the connect step if any selected platform is still missing a
      # credential. With the default `onboarding_platform: "both"`, a
      # GP-only credential add would leave ASC pending and re-route to
      # onboarding. Pin platform to "android" so the GP credential
      # satisfies the only platform the user said they ship to —
      # then the post-onboarding "back to org" path is exercised.
      user.update_columns(onboarding_platform: "android")

      post organization_google_play_credentials_path(organization), params: {
        google_play_credential: {
          name: "GP Key",
          service_account_json: {
            type: "service_account",
            project_id: "test",
            private_key: "-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----\n",
            client_email: "test@example.com",
            client_id: "123"
          }.to_json
        }
      }

      expect(response).to redirect_to(organization_path(organization))
    end
  end

  # ── Progress tracking ──────────────────────────────────────────────

  describe "progress tracking" do
    let(:organization) { create(:organization, owner: user) }

    before { sign_in_with_org(user, organization, onboarding_step: 2) }

    it "shows step indicators with correct completed states" do
      get onboarding_path(step: "token")
      doc = Nokogiri::HTML(response.body)

      controller_div = doc.at_css("[data-controller='onboarding']")
      expect(controller_div["data-onboarding-step-value"]).to eq("2")
      # The redesigned wizard rail has 6 visible steps (organization, cli,
      # token, token_created, connect, complete). `total-steps-value` is
      # `steps.size - 1` so the progress bar fills to 100% when the last
      # step is reached. See app/views/onboarding/_layout.html.erb.
      expect(controller_div["data-onboarding-total-steps-value"]).to eq("5")
    end
  end

  # ── Dashboard setup progress after onboarding ─────────────────────

  describe "dashboard setup progress respects onboarding" do
    let(:organization) { create(:organization, owner: user) }

    before do
      sign_in user, scope: :user
      user.update_columns(onboarding_completed_at: Time.current)
      post switch_organization_path(organization)
      ApiToken.generate_for(
        user: user,
        organization: organization,
        name: "CLI Token",
        scopes: %w[read write admin]
      )
    end

    it "does not show CLI install step for onboarded users on the setup progress widget" do
      get authenticated_root_path
      doc = Nokogiri::HTML(response.body)

      # The setup progress section should not contain an "Install the CLI" card
      setup_section = doc.at_css("#setup-progress-heading")&.parent
      if setup_section
        expect(setup_section.text).not_to include("Install the CLI")
      end
    end

    it "shows Google Play credentials step when missing" do
      get authenticated_root_path
      expect(response.body).to include("Add Google Play Credentials")
    end
  end
end
