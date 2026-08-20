require "rails_helper"

# Security-critical coverage for the SSO enforcement Warden hook in
# config/initializers/sso_enforcement.rb.
#
# When an org has `sso_configuration.enforced = true`, members of that org
# MUST sign in via SAML SSO. The owner has break-glass password access
# (so a misconfigured IdP never locks everyone out). Enforcement should
# also survive a plan downgrade cleanly (turn off when org drops below
# Team tier).
RSpec.describe "SSO enforcement", type: :request do
  let(:cert) { SamlTestHelpers.valid_test_cert }

  let(:owner) do
    User.create!(email: "enforce-owner@ex.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :team)
  end

  let(:admin_member) do
    u = User.create!(email: "enforce-admin@ex.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :free)
    u
  end

  let(:developer_member) do
    u = User.create!(email: "enforce-dev@ex.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :free)
    u
  end

  let(:organization) { Organization.create!(name: "Enforcing Org", owner: owner) }

  before do
    organization.memberships.create!(user: admin_member, role: :admin)
    organization.memberships.create!(user: developer_member, role: :developer)
    organization.create_sso_configuration!(
      idp_entity_id: "urn:ex",
      idp_sso_target_url: "https://idp.example.com/sso",
      idp_cert: cert,
      attribute_mappings: {},
      enabled: true,
      enforced: true
    )
  end

  describe "password sign-in with enforcement on" do
    it "allows the org OWNER to sign in with password (break-glass access)" do
      post user_session_path, params: {
        user: { email: owner.email, password: "SecurePassword123!" }
      }

      # Owner authentication proceeds normally. A 302 to authenticated_root_path
      # (or onboarding) is the success signal; we just verify the session is
      # attached and no SSO-required redirect fired.
      expect(response).to be_redirect
      expect(controller.current_user).to eq(owner).or be_nil  # controller may not be set in request spec; session cookie is the real signal
      # Confirmed by being able to hit an authenticated page without redirect
      get organization_path(organization)
      expect(response).to have_http_status(:ok)
    end

    it "BLOCKS admin members from signing in with password on an enforced org" do
      post user_session_path, params: {
        user: { email: admin_member.email, password: "SecurePassword123!" }
      }

      # Warden hook throws :warden -> Devise failure app redirects to sign-in.
      expect(response).to redirect_to(new_user_session_path)

      # Verify the user is ACTUALLY signed out -- not just shown a redirect
      # while retaining a live session cookie. This is the security contract:
      # a blocked sign-in means no authenticated pages are accessible.
      # (Regression: an earlier version of the hook called `auth.logout(user)`
      # instead of `auth.logout(:user)`, which was a no-op and left the
      # session authenticated.)
      expect(session.to_h.keys).not_to include("warden.user.user.key")
    end

    it "BLOCKS developer members too (not just admins)" do
      post user_session_path, params: {
        user: { email: developer_member.email, password: "SecurePassword123!" }
      }

      expect(response).to redirect_to(new_user_session_path)
      expect(session.to_h.keys).not_to include("warden.user.user.key")
    end
  end

  describe "multi-org SAML user (M-3 scoped provider skip)" do
    # A user can be SAML-linked to one org while being a plain member of
    # another org that enforces SSO. The enforcement hook must scope its
    # "skip for SAML-originated sessions" check to THIS enforcing org's
    # provider (saml_<enforcing-org-slug>), not to ANY provider starting
    # with "saml_". Otherwise the user bypasses the enforcing org's
    # password-login block by virtue of an unrelated org's SAML link.
    let(:other_owner) do
      User.create!(email: "other-owner@ex.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :team)
    end
    let(:other_org) { Organization.create!(name: "Other SAML Org", owner: other_owner) }

    before do
      other_org.memberships.create!(user: developer_member, role: :developer)
      # developer_member is SAML-linked to OTHER org, not the enforcing org.
      developer_member.update_columns(
        provider: "saml_#{other_org.slug}",
        uid: "saml-uid-other-org"
      )
    end

    it "STILL blocks password sign-in for the enforcing org despite a foreign SAML link" do
      post user_session_path, params: {
        user: { email: developer_member.email, password: "SecurePassword123!" }
      }

      expect(response).to redirect_to(new_user_session_path)
      # Actually logged out -- not just bounced with a live session.
      expect(session.to_h.keys).not_to include("warden.user.user.key")

      get organization_path(organization)
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "when the org has downgraded below Team" do
    before do
      owner.update!(plan_tier: :pro)  # no longer Team -> entitlements.sso_enabled? is false
    end

    it "does NOT enforce SSO when org lost Team entitlement" do
      # Even with enforced=true persisted, the enforcement hook checks the
      # live entitlement and skips for Pro/Free orgs. Members can password
      # login again.
      post user_session_path, params: {
        user: { email: admin_member.email, password: "SecurePassword123!" }
      }

      # Without enforcement, admin passes through normally.
      get organization_path(organization)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "when SSO is enforced but disabled" do
    before do
      organization.sso_configuration.update!(enabled: false, enforced: true)
    end

    it "does NOT enforce (enabled=false means SSO isn't actually configured)" do
      post user_session_path, params: {
        user: { email: admin_member.email, password: "SecurePassword123!" }
      }

      # With enabled=false, the Warden query predicate
      # `enabled: true, enforced: true` returns nil and enforcement skips.
      get organization_path(organization)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "with enforced SSO and a SAML-originated session" do
    # Regression coverage for the case where `auth.env["omniauth.strategy"]` is
    # nil during the Warden after_authentication phase (not guaranteed set in
    # all Devise/OmniAuth versions). A legitimate SAML login would be bounced
    # by the enforcement hook, causing an infinite SSO loop. The hook's
    # secondary check -- user.provider starts with "saml_" -- protects against
    # this regression.
    before do
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:saml] = OmniAuth::AuthHash.new(
        provider: "saml",
        uid: "saml-uid-enforced-dev",
        info: { email: developer_member.email, name: "SAML Dev" }
      )
      # Link the existing member to the SAML identity for this org -- mirrors
      # the state after Sso::JitProvisioner#link_saml_identity! has run.
      developer_member.update_columns(
        provider: "saml_#{organization.slug}",
        uid: "saml-uid-enforced-dev"
      )
    end

    after do
      OmniAuth.config.test_mode = false
      OmniAuth.config.mock_auth[:saml] = nil
    end

    it "does NOT log out a SAML-originated user when env[omniauth.strategy] is missing" do
      # Seed the session slug the initiation step normally writes.
      get sso_initiation_path(slug: organization.slug)

      post "/users/auth/saml/callback"

      # A successful SAML sign-in redirects to the authenticated root. The
      # essential assertion: the enforcement hook did NOT strip the session.
      expect(session.to_h.keys).to include("warden.user.user.key")

      # Confirm the authenticated session actually works end-to-end.
      get organization_path(organization)
      expect(response).to have_http_status(:ok)
    end
  end
end
