require "rails_helper"

RSpec.describe SsoInitiationsController, type: :request do
  let(:owner) do
    User.create!(email: "sso-init-owner@ex.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :team)
  end
  let(:organization) { Organization.create!(name: "SSO Init Org", owner: owner) }
  let(:cert) { SamlTestHelpers.valid_test_cert }

  before do
    organization.create_sso_configuration!(
      idp_entity_id: "urn:ex",
      idp_sso_target_url: "https://idp.example.com/sso",
      idp_cert: cert,
      attribute_mappings: {},
      enabled: true
    )
  end

  describe "GET /auth/sso" do
    it "renders the auto-submit form with a RelayState nonce when slug matches" do
      get sso_initiation_path(slug: organization.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("/users/auth/saml")
      expect(response.body).to include("RelayState")
    end

    it "renders the inline auto-submit <script> with a CSP nonce attribute" do
      # Production CSP is `script-src :self 'strict-dynamic'` with nonces
      # injected on the script-src directive. Without `nonce="..."` on this
      # inline tag the auto-submit silently no-ops in production and the
      # user must click the visible button instead.
      #
      # CSP / nonce generation is wired up in production env only (see
      # config/initializers/content_security_policy.rb) so in test env
      # `request.content_security_policy_nonce` returns nil and Rails
      # renders an empty `nonce=""` attribute. We verify only that the
      # ERB hook is present (i.e. the attribute renders at all on this
      # specific script tag); Rails owns the nonce-value logic.
      get sso_initiation_path(slug: organization.slug)

      # Capture the auto-submit <script> block specifically (there are
      # other <script> tags on the page from importmap / JSON-LD).
      auto_submit_script = response.body[
        %r{<script\s+nonce="[^"]*">\s*[^<]*document\.getElementById\("sso-auto-submit"\)\.submit\(\);[^<]*</script>}m
      ]
      expect(auto_submit_script).to be_present,
        "expected an auto-submit <script> tag with a nonce attribute, but none matched in:\n#{response.body[/<script[^>]*>[^<]*document\.getElementById\("sso-auto-submit"\)\.submit\(\);[^<]*<\/script>/m].inspect}"
    end

    it "generates a distinct nonce for each concurrent flow" do
      get sso_initiation_path(slug: organization.slug)
      body_1 = response.body
      nonce_1 = body_1[/name="RelayState"[^>]*value="([^"]+)"/, 1]
      expect(nonce_1).to be_present

      # Start a second concurrent flow (same session)
      get sso_initiation_path(slug: organization.slug)
      body_2 = response.body
      nonce_2 = body_2[/name="RelayState"[^>]*value="([^"]+)"/, 1]
      expect(nonce_2).to be_present

      expect(nonce_1).not_to eq(nonce_2)
    end

    it "generically redirects unknown slugs to sign_in without revealing existence" do
      get sso_initiation_path(slug: "no-such-org")

      expect(response).to redirect_to(new_user_session_path)
      follow_redirect!
      expect(response.body).to include("SSO is not available")
    end

    it "generically redirects when the org is not on Team tier" do
      owner.update!(plan_tier: :pro)

      get sso_initiation_path(slug: organization.slug)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects when slug is blank" do
      get sso_initiation_path(slug: "")
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
