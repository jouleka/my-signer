require "rails_helper"

RSpec.describe SamlMetadataController, type: :request do
  let(:owner) do
    User.create!(email: "meta-owner@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :team)
  end
  let(:organization) { Organization.create!(name: "Meta Team Org", owner: owner) }
  let(:cert) { SamlTestHelpers.valid_test_cert }

  describe "GET /saml/metadata/:slug" do
    it "returns 404 when no SSO config exists" do
      get saml_metadata_path(slug: organization.slug)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when SSO config exists but is disabled" do
      organization.create_sso_configuration!(
        idp_entity_id: "urn:x",
        idp_sso_target_url: "https://idp.example.com",
        idp_cert: cert,
        attribute_mappings: {},
        enabled: false
      )

      get saml_metadata_path(slug: organization.slug)
      expect(response).to have_http_status(:not_found)
    end

    it "returns SAML metadata XML when SSO is enabled" do
      organization.create_sso_configuration!(
        idp_entity_id: "urn:x",
        idp_sso_target_url: "https://idp.example.com",
        idp_cert: cert,
        attribute_mappings: {},
        enabled: true
      )

      get saml_metadata_path(slug: organization.slug)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("samlmetadata+xml")
      expect(response.body).to include("EntityDescriptor")
    end

    it "returns 404 for unknown slug" do
      get saml_metadata_path(slug: "nonexistent-slug")
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when SSO config is enabled but the org no longer has the Team entitlement" do
      organization.create_sso_configuration!(
        idp_entity_id: "urn:x",
        idp_sso_target_url: "https://idp.example.com",
        idp_cert: cert,
        attribute_mappings: {},
        enabled: true
      )
      # Downgrade the owner so `organization.entitlements.sso_enabled?` is false
      # while the SsoConfiguration row persists with enabled=true.
      owner.update!(plan_tier: :pro)

      get saml_metadata_path(slug: organization.slug)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "rate limiting" do
    # The metadata endpoint is unauthenticated, decrypts the IdP cert and
    # generates XML on every hit. Without a throttle a single attacker can
    # fan it out to make the app do nontrivial crypto work for free.
    #
    # We assert the throttle is REGISTERED rather than firing it end-to-end,
    # because Rack::Attack captures Rails.cache (NullStore in test env) at
    # boot time, so request-level throttles are no-ops in the test suite.
    # See PRODUCT_PIVOT_PLAN.md "Rack::Attack rate-limit automated specs --
    # middleware bypass in test env".
    it "registers an IP-based throttle for /saml/metadata/*" do
      throttle = Rack::Attack.throttles["sso/metadata/ip"]

      expect(throttle).to be_present
      expect(throttle.limit).to eq(30)
      expect(throttle.period).to eq(1.minute)
    end

    it "matches the metadata path with the configured throttle regex" do
      throttle = Rack::Attack.throttles["sso/metadata/ip"]
      env = Rack::MockRequest.env_for(saml_metadata_path(slug: "any-slug"))
      req = Rack::Attack::Request.new(env)

      # Discriminator block returns the IP if and only if the path matches
      # the throttle's regex.
      expect(throttle.block.call(req)).to eq(req.ip)
    end

    it "does not match unrelated paths" do
      throttle = Rack::Attack.throttles["sso/metadata/ip"]
      env = Rack::MockRequest.env_for("/up")
      req = Rack::Attack::Request.new(env)

      expect(throttle.block.call(req)).to be_nil
    end
  end
end
