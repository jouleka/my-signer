require "rails_helper"

RSpec.describe SsoConfigurationsController, type: :request do
  let(:team_owner) do
    User.create!(email: "team-sso-owner@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :team)
  end
  let(:organization) { Organization.create!(name: "SSO CRUD Org", owner: team_owner) }
  let(:cert) { SamlTestHelpers.valid_test_cert }
  let(:valid_params) do
    {
      sso_configuration: {
        idp_entity_id: "urn:ex",
        idp_sso_target_url: "https://idp.example.com/sso",
        idp_cert: cert,
        name_identifier_format: "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress",
        jit_default_role: "developer",
        enabled: "1",
        enforced: "0"
      }
    }
  end

  before { sign_in team_owner }

  describe "GET /organizations/:organization_id/sso_configuration" do
    it "renders show for a team-tier org admin even without existing config" do
      get organization_sso_configuration_path(organization)
      # Without a config, show redirects to new
      expect(response).to redirect_to(new_organization_sso_configuration_path(organization))
    end
  end

  describe "GET /organizations/:organization_id/sso_configuration/new" do
    it "renders the form successfully (regression: form previously crashed on singular-resource route helper)" do
      get new_organization_sso_configuration_path(organization)

      expect(response).to have_http_status(:ok)
      # Form should reference the singular create URL, not a pluralized one
      expect(response.body).to include(organization_sso_configuration_path(organization))
      expect(response.body).to include("IdP Entity ID") | include("entity")
    end

    it "renders the edit form successfully when a config already exists" do
      organization.create_sso_configuration!(
        idp_entity_id: "urn:existing",
        idp_sso_target_url: "https://existing.example.com/sso",
        idp_cert: cert,
        attribute_mappings: {},
        enabled: false
      )

      get edit_organization_sso_configuration_path(organization)

      expect(response).to have_http_status(:ok)
      # Edit form should also reference the singular update URL
      expect(response.body).to include(organization_sso_configuration_path(organization))
      # And use PATCH method (Rails emits a hidden _method field for non-POST)
      expect(response.body).to include("patch")
    end

    it "includes the redesigned preset shortcut row and SP-details sidecar" do
      get new_organization_sso_configuration_path(organization)

      # Preset buttons are the Stimulus-driven quick-start UI
      expect(response.body).to include('data-preset="okta"')
      expect(response.body).to include('data-preset="azure"')
      expect(response.body).to include('data-preset="google"')
      expect(response.body).to include('data-preset="custom"')
      # SP details sidecar shows the generated ACS URL
      expect(response.body).to include("users/auth/saml/callback")
      expect(response.body).to include("saml/metadata/#{organization.slug}")
      # The ambiguous in-form "Cancel" button was replaced by a contextual
      # back link that tells the user exactly where they're going.
      expect(response.body).to include("Back to organization")
    end

    it "renders the verified_domains field (cross-org identity-theft defense)" do
      get new_organization_sso_configuration_path(organization)
      expect(response.body).to include('id="sso-verified-domains"')
      expect(response.body).to include("Verified email domains")
    end
  end

  describe "non-admin access guards on a Team-tier org" do
    # Security-critical: even on a Team-tier org, non-admin members (developers,
    # viewers) must NOT be able to view, create, edit, or remove the SSO
    # configuration. Only org admins and the owner can manage SSO.
    let(:developer) do
      u = User.create!(email: "sso-dev@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :free)
      organization.memberships.create!(user: u, role: :developer)
      u
    end
    let(:viewer) do
      u = User.create!(email: "sso-viewer@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :free)
      organization.memberships.create!(user: u, role: :viewer)
      u
    end

    it "blocks developers from viewing the SSO show page" do
      sign_out team_owner
      sign_in developer

      get organization_sso_configuration_path(organization)
      expect(response).not_to have_http_status(:ok)
      expect(response).to be_redirect
    end

    it "blocks developers from creating a new SSO configuration" do
      sign_out team_owner
      sign_in developer

      post organization_sso_configuration_path(organization), params: valid_params

      expect(response).not_to have_http_status(:ok)
      expect(response).to be_redirect
      expect(organization.reload.sso_configuration).to be_nil
    end

    it "blocks viewers from every SSO route" do
      organization.create_sso_configuration!(
        idp_entity_id: "urn:existing",
        idp_sso_target_url: "https://existing.example.com/sso",
        idp_cert: cert,
        attribute_mappings: {},
        enabled: true
      )
      sign_out team_owner
      sign_in viewer

      [
        -> { get organization_sso_configuration_path(organization) },
        -> { get new_organization_sso_configuration_path(organization) },
        -> { get edit_organization_sso_configuration_path(organization) },
        -> { post organization_sso_configuration_path(organization), params: valid_params },
        -> { delete organization_sso_configuration_path(organization) }
      ].each do |call|
        call.call
        expect(response).not_to have_http_status(:ok), "Expected viewer to be denied, got 200: #{response.body[0..200]}"
      end
    end
  end

  describe "POST /organizations/:organization_id/sso_configuration" do
    it "creates a new SSO configuration on Team tier" do
      expect {
        post organization_sso_configuration_path(organization), params: valid_params
      }.to change { organization.reload.sso_configuration.present? }.from(false).to(true)

      expect(response).to redirect_to(organization_sso_configuration_path(organization))
    end

    it "persists verified_domains from the textarea accessor, normalized" do
      params_with_domains = valid_params.deep_dup
      params_with_domains[:sso_configuration][:verified_domains_text] =
        "ACME.com\nacme.io\n acme.com "

      post organization_sso_configuration_path(organization), params: params_with_domains

      config = organization.reload.sso_configuration
      expect(config).to be_present
      expect(config.verified_domains).to eq([ "acme.com", "acme.io" ])
    end

    context "when the org is not on Team plan" do
      before { team_owner.update!(plan_tier: :pro) }

      it "renders the Team-feature paywall and does not create the config" do
        post organization_sso_configuration_path(organization), params: valid_params
        # The before_action :require_sso_entitlement! short-circuits with the
        # paywall page (200 OK with the upgrade UI). Crucially, the config
        # is NOT saved.
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Single Sign-On")
        expect(response.body).to include("Team feature")
        expect(organization.reload.sso_configuration).to be_nil
      end

      it "renders the paywall on GET show as well" do
        get organization_sso_configuration_path(organization)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Single Sign-On")
        expect(response.body).to include("Upgrade to Team")
      end
    end
  end

  describe "PATCH /organizations/:organization_id/sso_configuration" do
    before do
      organization.create_sso_configuration!(
        idp_entity_id: "urn:existing",
        idp_sso_target_url: "https://old.example.com/sso",
        idp_cert: cert,
        attribute_mappings: {},
        enabled: false
      )
    end

    it "updates the existing config" do
      patch organization_sso_configuration_path(organization), params: {
        sso_configuration: { idp_sso_target_url: "https://new.example.com/sso" }
      }

      expect(response).to redirect_to(organization_sso_configuration_path(organization))
      expect(organization.sso_configuration.reload.idp_sso_target_url).to eq("https://new.example.com/sso")
    end
  end

  describe "DELETE /organizations/:organization_id/sso_configuration" do
    before do
      organization.create_sso_configuration!(
        idp_entity_id: "urn:delete",
        idp_sso_target_url: "https://x.example.com",
        idp_cert: cert,
        attribute_mappings: {}
      )
    end

    it "destroys the SSO configuration" do
      expect {
        delete organization_sso_configuration_path(organization)
      }.to change { organization.reload.sso_configuration }.from(SsoConfiguration).to(nil)

      expect(response).to redirect_to(organization_path(organization))
    end
  end
end
