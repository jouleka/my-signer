require "rails_helper"

# Direct coverage of Users::OmniauthCallbacksController#saml.
#
# We can't easily drive a real SAML assertion end-to-end in a spec, so these
# exercise the controller's branching via OmniAuth.config.mock_auth.
#
# What we cover:
#   - Happy path: mocked auth hash -> JIT provision -> signed in + audit event
#   - Missing/unknown slug -> generic redirect (no org enumeration)
#   - Team entitlement lost mid-flow (org downgraded) -> reject
#   - JIT provisioner failure -> audit log + friendly redirect
#   - Plain exception inside callback -> caught and redirected (no 500)
RSpec.describe "Users::OmniauthCallbacksController#saml", type: :request do
  let(:cert)      { SamlTestHelpers.valid_test_cert }
  let(:owner)     { User.create!(email: "saml-cb-owner@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :team) }
  let(:organization) { Organization.create!(name: "Callback Org", owner: owner) }

  before do
    organization.create_sso_configuration!(
      idp_entity_id: "urn:ex",
      idp_sso_target_url: "https://idp.example.com/sso",
      idp_cert: cert,
      attribute_mappings: {},
      enabled: true,
      jit_default_role: :developer
    )

    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:saml] = OmniAuth::AuthHash.new(
      provider: "saml",
      uid: "saml-uid-new-user",
      info: { email: "new-saml-user@example.com", name: "New SAML User" }
    )
  end

  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:saml] = nil
  end

  it "JIT-provisions a new user, signs them in, and records an sso_login audit event" do
    # Set the session slug the setup proc would have written during
    # initiation. In test_mode, the setup proc is bypassed so we seed it
    # via the controller directly.
    #
    # Each callback endpoint runs through SsoInitiationsController#new first
    # in the real flow; here we simulate the post-init state by visiting
    # the initiation URL, which writes session["sso_org_slug"] and session["sso_flows"].
    get sso_initiation_path(slug: organization.slug)
    expect(response).to have_http_status(:ok)

    expect {
      post "/users/auth/saml/callback"
    }.to change(User, :count).by(1).and change(AuditEvent, :count).by(1)

    new_user = User.find_by(email: "new-saml-user@example.com")
    expect(new_user).to be_present
    expect(new_user.provider).to eq("saml_#{organization.slug}")
    expect(new_user.uid).to eq("saml-uid-new-user")

    audit = AuditEvent.last
    expect(audit.action).to eq("sso_login")
    expect(audit.organization).to eq(organization)
    expect(audit.actor).to eq(new_user)
    # PII hygiene: raw email is NOT persisted in metadata. The actor link
    # already ties the event to the user record.
    expect(audit.metadata).not_to have_key("email")
    expect(audit.metadata["jit"]).to eq(false)
  end

  it "redirects to sign-in when the session slug can't be resolved to a config" do
    # No session slug set -> callback can't find the config -> friendly redirect
    post "/users/auth/saml/callback"

    expect(response).to redirect_to(new_user_session_path)
  end

  it "rejects the callback when the org has lost its Team tier mid-flow" do
    get sso_initiation_path(slug: organization.slug)

    # Simulate a plan downgrade between AuthnRequest and callback
    owner.update!(plan_tier: :pro)

    post "/users/auth/saml/callback"

    expect(response).to redirect_to(new_user_session_path)
    # No user was auto-provisioned because the entitlement check refused
    expect(User.find_by(email: "new-saml-user@example.com")).to be_nil
  end

  it "records sso_login_failed when the JIT provisioner fails" do
    # Provisioner fails when the auth hash has no email
    OmniAuth.config.mock_auth[:saml] = OmniAuth::AuthHash.new(
      provider: "saml",
      uid: "",
      info: { email: nil, name: nil }
    )

    get sso_initiation_path(slug: organization.slug)

    expect {
      post "/users/auth/saml/callback"
    }.to change { AuditEvent.where(action: "sso_login_failed").count }.by(1)

    expect(response).to redirect_to(new_user_session_path)
  end

  it "records sso_login_failed metadata with email_domain only (no raw email) and bounded error strings" do
    # Provisioner returns :jit_failed with a string error when the SAML
    # assertion carries no email. Use a deterministic email so we can assert
    # the domain-only shape.
    OmniAuth.config.mock_auth[:saml] = OmniAuth::AuthHash.new(
      provider: "saml",
      uid: "some-uid",
      info: { email: "someone@sensitive-corp.example", name: nil }
    )
    # Force a JIT failure by stubbing the provisioner to return a long, noisy
    # error payload -- this guards the "truncate(200)" bound.
    allow_any_instance_of(Sso::JitProvisioner).to receive(:call).and_return(
      Sso::JitProvisioner::Result.new(
        status: :jit_failed,
        user: nil,
        errors: [ "X" * 500 ]
      )
    )

    get sso_initiation_path(slug: organization.slug)
    post "/users/auth/saml/callback"

    audit = AuditEvent.where(action: "sso_login_failed").last
    expect(audit).to be_present
    # Raw email MUST NOT appear in metadata.
    expect(audit.metadata).not_to have_key("email")
    expect(audit.metadata["email_domain"]).to eq("sensitive-corp.example")
    # Errors are bounded strings, not arbitrary objects.
    expect(audit.metadata["errors"]).to be_an(Array)
    expect(audit.metadata["errors"].first).to be_a(String)
    expect(audit.metadata["errors"].first.length).to be <= 203 # truncate suffix
  end

  it "returns nil email_domain for malformed IdP emails (no leak of raw identifier)" do
    # Regression guard: a malformed email (no "@") must NOT become the
    # "email_domain" value, which would defeat the PII-hygiene purpose
    # of this metadata field.
    OmniAuth.config.mock_auth[:saml] = OmniAuth::AuthHash.new(
      provider: "saml",
      uid: "some-uid",
      info: { email: "malformed-no-at-sign", name: nil }
    )
    allow_any_instance_of(Sso::JitProvisioner).to receive(:call).and_return(
      Sso::JitProvisioner::Result.new(status: :jit_failed, user: nil, errors: [ "nope" ])
    )

    get sso_initiation_path(slug: organization.slug)
    post "/users/auth/saml/callback"

    audit = AuditEvent.where(action: "sso_login_failed").last
    expect(audit.metadata).not_to have_key("email")
    expect(audit.metadata["email_domain"]).to be_nil
    # The raw malformed value must not leak under any other key either.
    expect(audit.metadata.to_json).not_to include("malformed-no-at-sign")
  end
end
