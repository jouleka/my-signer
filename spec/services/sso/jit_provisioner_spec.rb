require "rails_helper"

RSpec.describe Sso::JitProvisioner do
  let(:owner) do
    User.create!(email: "sso-owner-jit@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :team)
  end
  let(:organization) { Organization.create!(name: "JIT Team Org", owner: owner) }
  let(:cert) { SamlTestHelpers.valid_test_cert }
  let(:config) do
    SsoConfiguration.create!(
      organization: organization,
      idp_entity_id: "urn:ex",
      idp_sso_target_url: "https://idp.example.com/sso",
      idp_cert: cert,
      attribute_mappings: {},
      enabled: true,
      jit_default_role: :developer
    )
  end

  def build_auth(email:, name: nil, uid: "saml-uid-123")
    OmniAuth::AuthHash.new(
      provider: "saml",
      uid: uid,
      info: { email: email, name: name }
    )
  end

  describe "#call" do
    it "creates a new user and membership on first SSO login" do
      config  # force evaluation so counters don't include setup
      auth = build_auth(email: "new-jit@example.com", name: "New JIT User")

      result = nil
      expect {
        result = described_class.new(auth, config).call
      }.to change(User, :count).by(1).and change(Membership, :count).by(1)

      expect(result.status).to eq(:ok)
      expect(result.user.email).to eq("new-jit@example.com")
      expect(result.user.provider).to eq("saml_#{organization.slug}")
      expect(result.user.uid).to eq("saml-uid-123")
      expect(organization.memberships.find_by(user: result.user).role).to eq("developer")
    end

    it "links an existing user by email on first SSO login without creating new user" do
      config.update!(verified_domains: [ "example.com" ])
      existing = User.create!(email: "existing@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :free)
      auth = build_auth(email: "existing@example.com", name: "Existing User", uid: "saml-uid-456")

      result = nil
      expect {
        result = described_class.new(auth, config).call
      }.to change(User, :count).by(0).and change(Membership, :count).by(1)

      expect(result.status).to eq(:ok)
      expect(result.user).to eq(existing)
      expect(existing.reload.provider).to eq("saml_#{organization.slug}")
      expect(existing.uid).to eq("saml-uid-456")
    end

    it "finds a returning SSO user by provider+uid (no email lookup)" do
      returning = User.create!(
        email: "returning@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :free,
        provider: "saml_#{organization.slug}", uid: "saml-uid-returning"
      )
      organization.memberships.create!(user: returning, role: :developer)
      auth = build_auth(email: "returning@example.com", uid: "saml-uid-returning")

      result = described_class.new(auth, config).call

      expect(result.status).to eq(:ok)
      expect(result.user).to eq(returning)
    end

    it "does not overwrite a non-SAML OAuth provider on an existing user" do
      config.update!(verified_domains: [ "example.com" ])
      google_user = User.create!(
        email: "google-user@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :free,
        provider: "google_oauth2", uid: "google-123"
      )
      auth = build_auth(email: "google-user@example.com", uid: "saml-uid-999")

      result = described_class.new(auth, config).call

      expect(result.status).to eq(:ok)
      expect(google_user.reload.provider).to eq("google_oauth2")  # Preserved
      expect(google_user.uid).to eq("google-123")
    end

    it "returns :locked when the user is locked" do
      config.update!(verified_domains: [ "example.com" ])
      locked = User.create!(
        email: "locked@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :free,
        locked_at: Time.current
      )
      auth = build_auth(email: "locked@example.com")

      result = described_class.new(auth, config).call

      expect(result.status).to eq(:locked)
    end

    it "returns :pending_deletion without mutating a soft-deleted user matched by (provider, uid)" do
      returning = User.create!(
        email: "soft-deleted-pu@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :free,
        provider: "saml_#{organization.slug}", uid: "saml-uid-soft-deleted"
      )
      returning.soft_delete!
      original_provider = returning.reload.provider
      original_uid = returning.uid

      auth = build_auth(email: "soft-deleted-pu@example.com", uid: "saml-uid-soft-deleted")

      expect {
        result = described_class.new(auth, config).call
        expect(result.status).to eq(:pending_deletion)
        expect(result.user).to be_nil
      }.to change(Membership, :count).by(0)

      returning.reload
      expect(returning.provider).to eq(original_provider)
      expect(returning.uid).to eq(original_uid)
    end

    it "returns :pending_deletion without mutating a soft-deleted user matched by email" do
      config.update!(verified_domains: [ "example.com" ])
      existing = User.create!(email: "soft-deleted-em@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :free)
      existing.soft_delete!

      auth = build_auth(email: "soft-deleted-em@example.com", uid: "saml-uid-fresh")

      expect {
        result = described_class.new(auth, config).call
        expect(result.status).to eq(:pending_deletion)
        expect(result.user).to be_nil
      }.to change(Membership, :count).by(0).and change(User, :count).by(0)

      existing.reload
      expect(existing.provider).to be_blank
      expect(existing.uid).to be_blank
    end

    it "returns :jit_failed when no email is provided" do
      auth = OmniAuth::AuthHash.new(provider: "saml", uid: "", info: { email: nil })

      result = described_class.new(auth, config).call

      expect(result.status).to eq(:jit_failed)
      expect(result.errors).to include(/No email/)
    end
  end

  describe "verified_domains gate (cross-org identity-theft defense)" do
    # Without this gate, a Team-tier admin with their own IdP could claim any
    # existing password-only user's email in a SAMLResponse and silently link
    # the victim's account to the attacker's IdP. Every existing-user
    # auto-link now goes through SsoConfiguration#email_domain_verified?.

    it "auto-links an existing user when the email domain IS in verified_domains" do
      config.update!(verified_domains: [ "trusted.example" ])
      existing = User.create!(
        email: "alice@trusted.example",
        password: "SecurePassword123!",
        confirmed_at: Time.current,
        plan_tier: :free
      )
      auth = build_auth(email: "alice@trusted.example", uid: "saml-uid-trusted")

      result = described_class.new(auth, config).call

      expect(result.status).to eq(:ok)
      expect(result.user).to eq(existing)
      expect(existing.reload.provider).to eq("saml_#{organization.slug}")
    end

    it "refuses the link when the email domain is NOT in verified_domains (attack path)" do
      config.update!(verified_domains: [ "trusted.example" ])
      victim = User.create!(
        email: "victim@other-corp.example",
        password: "SecurePassword123!",
        confirmed_at: Time.current,
        plan_tier: :free
      )
      auth = build_auth(email: "victim@other-corp.example", uid: "attacker-uid")

      result = nil
      expect {
        result = described_class.new(auth, config).call
      }.to change(User, :count).by(0).and change(Membership, :count).by(0)

      expect(result.status).to eq(:domain_not_verified)
      expect(result.errors.join).to match(/verified domains/i)
      # Victim's provider/uid must be unchanged -- no silent takeover.
      expect(victim.reload.provider).to be_nil
      expect(victim.uid).to be_nil
    end

    it "still provisions brand-new users even when verified_domains is empty" do
      # Brand-new users have no existing account to steal, so the gate does
      # not apply. Fresh JIT-create stays open.
      config  # force evaluation
      expect(config.verified_domains).to eq([])
      auth = build_auth(email: "brand-new@anydomain.example", name: "Brand New", uid: "saml-uid-new")

      result = nil
      expect {
        result = described_class.new(auth, config).call
      }.to change(User, :count).by(1)

      expect(result.status).to eq(:ok)
      expect(result.user.email).to eq("brand-new@anydomain.example")
    end

    it "skips the domain check for an already-SAML-linked user" do
      # A user already carrying provider=saml_<slug> + matching uid belongs to
      # this org. No email re-lookup and therefore no domain check.
      config  # empty verified_domains
      returning = User.create!(
        email: "returning@some-domain.example",
        password: "SecurePassword123!",
        confirmed_at: Time.current,
        plan_tier: :free,
        provider: "saml_#{organization.slug}",
        uid: "saml-uid-returning"
      )
      organization.memberships.create!(user: returning, role: :developer)
      auth = build_auth(email: "returning@some-domain.example", uid: "saml-uid-returning")

      result = described_class.new(auth, config).call

      expect(result.status).to eq(:ok)
      expect(result.user).to eq(returning)
    end

    it "refuses any existing-user auto-link when verified_domains is empty (fail-safe default)" do
      # Fresh SSO config with no verified_domains yet: admins must explicitly
      # opt in a domain before any existing user can be auto-linked.
      config  # empty verified_domains
      existing = User.create!(
        email: "pre-sso@example.com",
        password: "SecurePassword123!",
        confirmed_at: Time.current,
        plan_tier: :free
      )
      auth = build_auth(email: "pre-sso@example.com", uid: "saml-uid-pre")

      result = described_class.new(auth, config).call

      expect(result.status).to eq(:domain_not_verified)
      expect(existing.reload.provider).to be_nil
    end
  end
end
