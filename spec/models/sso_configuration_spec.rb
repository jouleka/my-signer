require "rails_helper"

RSpec.describe SsoConfiguration do
  let(:owner) do
    User.create!(email: "sso-owner@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :team)
  end
  let(:organization) { Organization.create!(name: "SSO Team Org", owner: owner) }
  let(:cert) { SamlTestHelpers.valid_test_cert }

  describe "validations" do
    it "requires idp_entity_id, idp_sso_target_url, and idp_cert" do
      config = described_class.new(organization: organization)
      expect(config).not_to be_valid
      expect(config.errors[:idp_entity_id]).to be_present
      expect(config.errors[:idp_sso_target_url]).to be_present
      expect(config.errors[:idp_cert]).to be_present
    end

    it "requires idp_sso_target_url to be an https URL" do
      config = described_class.new(
        organization: organization,
        idp_entity_id: "urn:example",
        idp_sso_target_url: "not-a-url",
        idp_cert: cert,
        attribute_mappings: {}
      )
      expect(config).not_to be_valid
      expect(config.errors[:idp_sso_target_url]).to include(/https/)
    end

    it "rejects plain http:// IdP URLs (SAML secrets must not ride cleartext)" do
      config = described_class.new(
        organization: organization,
        idp_entity_id: "urn:example",
        idp_sso_target_url: "http://idp.example.com/sso",
        idp_cert: cert,
        attribute_mappings: {}
      )
      expect(config).not_to be_valid
      expect(config.errors[:idp_sso_target_url]).to be_present
    end

    it "requires org to be on Team plan" do
      owner.update!(plan_tier: :pro)
      config = described_class.new(
        organization: organization,
        idp_entity_id: "urn:ex",
        idp_sso_target_url: "https://idp.example.com",
        idp_cert: cert,
        attribute_mappings: {}
      )
      expect(config).not_to be_valid
      expect(config.errors[:base]).to include(/Team plan/)
    end

    it "requires idp_cert to be PEM-formatted" do
      config = described_class.new(
        organization: organization,
        idp_entity_id: "urn:ex",
        idp_sso_target_url: "https://idp.example.com",
        idp_cert: "garbage",
        attribute_mappings: {}
      )
      expect(config).not_to be_valid
      expect(config.errors[:idp_cert]).to include(/PEM/)
    end

    it "rejects a string that has PEM markers but invalid cert contents" do
      config = described_class.new(
        organization: organization,
        idp_entity_id: "urn:ex",
        idp_sso_target_url: "https://idp.example.com",
        idp_cert: "-----BEGIN CERTIFICATE-----\nNOT_REAL_BASE64\n-----END CERTIFICATE-----",
        attribute_mappings: {}
      )
      expect(config).not_to be_valid
      expect(config.errors[:idp_cert].join).to match(/x509|not a valid|certificate/i)
    end

    it "saves with all required fields and Team plan" do
      config = described_class.new(
        organization: organization,
        idp_entity_id: "urn:ex",
        idp_sso_target_url: "https://idp.example.com",
        idp_cert: cert,
        attribute_mappings: { "email" => "urn:emailClaim" }
      )
      expect(config).to be_valid
    end
  end

  describe "verified_domains" do
    let(:base_attrs) do
      {
        organization: organization,
        idp_entity_id: "urn:ex",
        idp_sso_target_url: "https://idp.example.com",
        idp_cert: cert,
        attribute_mappings: {}
      }
    end

    it "defaults to an empty array when not set" do
      config = described_class.create!(base_attrs)
      expect(config.verified_domains).to eq([])
    end

    it "normalizes entries: downcase, strip, dedupe, reject blanks" do
      config = described_class.create!(
        base_attrs.merge(verified_domains: [ " ACME.com ", "acme.com", "", "  ", "sub.Acme.IO" ])
      )
      expect(config.verified_domains).to eq([ "acme.com", "sub.acme.io" ])
    end

    it "rejects values containing an '@' sign" do
      config = described_class.new(base_attrs.merge(verified_domains: [ "acme@com" ]))
      expect(config).not_to be_valid
      expect(config.errors[:verified_domains].join).to match(/invalid domain/i)
    end

    it "rejects values with a scheme or path" do
      config = described_class.new(base_attrs.merge(verified_domains: [ "https://acme.com" ]))
      expect(config).not_to be_valid
      expect(config.errors[:verified_domains]).to be_present
    end

    it "rejects values with whitespace inside" do
      # After normalization we strip leading/trailing whitespace, but an
      # internal space is not a legal domain label character.
      config = described_class.new(base_attrs.merge(verified_domains: [ "acme com" ]))
      expect(config).not_to be_valid
      expect(config.errors[:verified_domains]).to be_present
    end

    it "rejects values with a slash" do
      config = described_class.new(base_attrs.merge(verified_domains: [ "acme.com/path" ]))
      expect(config).not_to be_valid
      expect(config.errors[:verified_domains]).to be_present
    end

    it "rejects values without a dot (single-label)" do
      config = described_class.new(base_attrs.merge(verified_domains: [ "acme" ]))
      expect(config).not_to be_valid
      expect(config.errors[:verified_domains]).to be_present
    end

    it "accepts multi-label and hyphenated domains" do
      config = described_class.new(
        base_attrs.merge(verified_domains: [ "acme.co.uk", "my-org.example" ])
      )
      expect(config).to be_valid
    end

    describe "#verified_domains_text accessor" do
      it "maps text input to the underlying array (newline-separated)" do
        config = described_class.new(base_attrs)
        config.verified_domains_text = "acme.com\nacme.io"
        expect(config.verified_domains).to eq([ "acme.com", "acme.io" ])
      end

      it "also handles comma-separated input" do
        config = described_class.new(base_attrs)
        config.verified_domains_text = "acme.com, acme.io"
        expect(config.verified_domains.map(&:strip)).to include("acme.com", "acme.io")
      end

      it "renders the array as newline-joined text for form display" do
        config = described_class.create!(base_attrs.merge(verified_domains: [ "acme.com", "acme.io" ]))
        expect(config.verified_domains_text).to eq("acme.com\nacme.io")
      end
    end
  end

  describe "#email_domain_verified?" do
    let(:config) do
      described_class.create!(
        organization: organization,
        idp_entity_id: "urn:ex",
        idp_sso_target_url: "https://idp.example.com",
        idp_cert: cert,
        attribute_mappings: {},
        verified_domains: [ "acme.com" ]
      )
    end

    it "returns true when the email's domain exactly matches a verified entry" do
      expect(config.email_domain_verified?("alice@acme.com")).to be true
    end

    it "is case-insensitive on the email side" do
      expect(config.email_domain_verified?("Alice@ACME.com")).to be true
    end

    it "strips whitespace around the email" do
      expect(config.email_domain_verified?("  alice@acme.com  ")).to be true
    end

    it "returns false for a non-matching domain" do
      expect(config.email_domain_verified?("alice@evil.example")).to be false
    end

    it "returns false when verified_domains is empty" do
      config.update!(verified_domains: [])
      expect(config.email_domain_verified?("alice@acme.com")).to be false
    end

    it "returns false for nil input" do
      expect(config.email_domain_verified?(nil)).to be false
    end

    it "returns false for malformed input (no '@')" do
      expect(config.email_domain_verified?("not-an-email")).to be false
    end

    it "returns false for an empty string" do
      expect(config.email_domain_verified?("")).to be false
    end

    it "still matches the domain when the local-part is empty but '@' is present" do
      # Not a security concern in practice: Devise rejects empty local-part
      # emails at the user model, so `existing.email` reaching this method
      # would never be "@acme.com". Documenting the actual behavior.
      expect(config.email_domain_verified?("@acme.com")).to be true
    end

    it "returns false when the domain-part is empty" do
      expect(config.email_domain_verified?("alice@")).to be false
    end
  end

  describe "at-rest encryption" do
    # Regression guard: SsoConfiguration#idp_cert holds sensitive IdP public-key
    # material and is declared with `encrypts :idp_cert`. If that declaration
    # is ever removed or the encryption layer regresses, this spec fails loudly
    # because the raw DB column would contain the PEM markers in plaintext.
    it "encrypts idp_cert at rest" do
      config = described_class.create!(
        organization: organization,
        idp_entity_id: "urn:ex",
        idp_sso_target_url: "https://idp.example.com",
        idp_cert: cert,
        attribute_mappings: {}
      )

      raw = described_class.connection.select_value(
        described_class.sanitize_sql_array(
          [ "SELECT idp_cert FROM sso_configurations WHERE id = ?", config.id ]
        )
      )

      expect(raw).not_to be_blank
      expect(raw).not_to include("-----BEGIN CERTIFICATE-----")
      # Sanity: the attribute reader still returns the plaintext PEM
      expect(config.reload.idp_cert).to include("-----BEGIN CERTIFICATE-----")
    end
  end

  describe "#sp_entity_id and #acs_url" do
    let(:config) do
      described_class.new(
        organization: organization,
        idp_entity_id: "urn:ex",
        idp_sso_target_url: "https://idp.example.com",
        idp_cert: cert,
        attribute_mappings: {}
      )
    end

    it "derives SP entity ID from org slug" do
      expect(config.sp_entity_id).to include("/saml/metadata/#{organization.slug}")
    end

    it "produces a fixed ACS URL" do
      expect(config.acs_url).to include("/users/auth/saml/callback")
    end
  end

  describe "#to_omniauth_options" do
    let(:config) do
      described_class.new(
        organization: organization,
        idp_entity_id: "urn:ex",
        idp_sso_target_url: "https://idp.example.com",
        idp_cert: cert,
        attribute_mappings: {}
      )
    end

    it "returns the hash shape expected by omniauth-saml" do
      opts = config.to_omniauth_options

      expect(opts[:idp_entity_id]).to eq("urn:ex")
      expect(opts[:idp_sso_target_url]).to eq("https://idp.example.com")
      expect(opts[:idp_cert]).to eq(cert)
      expect(opts[:sp_entity_id]).to include("/saml/metadata/#{organization.slug}")
      expect(opts[:security][:want_assertions_signed]).to be true
      expect(opts[:allowed_clock_drift]).to eq(30)
    end
  end

  describe "#consume_assertion! (L-8 replay protection)" do
    let(:config) do
      organization.create_sso_configuration!(
        idp_entity_id: "urn:ex",
        idp_sso_target_url: "https://idp.example.com",
        idp_cert: cert,
        attribute_mappings: {},
        enabled: true
      )
    end

    # The test env uses :null_store (config/environments/test.rb), which never
    # retains writes -- so a replay would appear "fresh" forever. Swap in a
    # real MemoryStore for these examples so check-and-set semantics are
    # actually exercised.
    around do |example|
      previous = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = previous
    end

    it "allows the first use of an assertion ID and REJECTS the replay" do
      assertion_id = "_#{SecureRandom.hex(16)}"

      expect(config.consume_assertion!(assertion_id, validity_window: 5.minutes)).to be_truthy
      # Same ID a second time = replay -> must fail closed.
      expect(config.consume_assertion!(assertion_id, validity_window: 5.minutes)).to be_falsey
    end

    it "fails closed when the assertion ID is blank (cannot prove uniqueness)" do
      expect(config.consume_assertion!(nil)).to be_falsey
      expect(config.consume_assertion!("")).to be_falsey
      expect(config.consume_assertion!("   ")).to be_falsey
    end

    it "treats distinct assertion IDs independently" do
      expect(config.consume_assertion!("_aaa")).to be_truthy
      expect(config.consume_assertion!("_bbb")).to be_truthy
    end

    it "scopes the replay namespace per config so two orgs don't collide" do
      other_owner = User.create!(email: "replay-other@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :team)
      other_org = Organization.create!(name: "Replay Other Org", owner: other_owner)
      other_config = other_org.create_sso_configuration!(
        idp_entity_id: "urn:ex2",
        idp_sso_target_url: "https://idp2.example.com",
        idp_cert: cert,
        attribute_mappings: {},
        enabled: true
      )

      shared_id = "_#{SecureRandom.hex(8)}"
      expect(config.consume_assertion!(shared_id)).to be_truthy
      # Same raw ID, different org -> not a replay against the other config.
      expect(other_config.consume_assertion!(shared_id)).to be_truthy
      # But a true replay within the same org is still blocked.
      expect(config.consume_assertion!(shared_id)).to be_falsey
    end

    it "sets a TTL that outlives the assertion validity window by the clock drift" do
      assertion_id = "_#{SecureRandom.hex(8)}"
      expect(Rails.cache).to receive(:write).with(
        a_string_including(SsoConfiguration::REPLAY_GUARD_CACHE_NAMESPACE),
        anything,
        hash_including(unless_exist: true, expires_in: 300 + config.assertion_clock_drift_seconds)
      ).and_return(true)

      config.consume_assertion!(assertion_id, validity_window: 5.minutes)
    end
  end
end
