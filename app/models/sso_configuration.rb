class SsoConfiguration < ApplicationRecord
  # Per-organization SAML 2.0 SSO configuration. Team-tier only -- validation
  # below refuses to save unless the org's entitlements include sso_enabled.
  #
  # The `idp_cert` column stores the IdP's x509 public certificate. It is
  # encrypted at rest via ActiveRecord::Encryption.
  encrypts :idp_cert

  belongs_to :organization

  # Matches Membership::role integer enum. Owner is NOT a valid default --
  # JIT-provisioned users should never auto-become owners.
  JIT_ROLES = { admin: 0, developer: 1, viewer: 2 }.freeze
  enum :jit_default_role, JIT_ROLES, prefix: true, default: :developer

  validates :idp_entity_id, presence: true
  validates :idp_sso_target_url, presence: true, format: { with: /\Ahttps:\/\/[^\s]+\z/, message: "must be an https:// URL" }
  validates :idp_cert, presence: true
  validate  :organization_on_team_plan, on: [ :create, :update ]
  validate  :cert_format
  validate  :verified_domains_format

  # Normalize verified_domains before validation. Ensures canonical,
  # lowercase, whitespace-free entries with no duplicates or blanks.
  before_validation :normalize_verified_domains

  # Domain-like pattern: one or more label groups separated by dots, with
  # at least one dot. Matches `acme.com`, `sub.acme.co.uk`, `x.y`.
  # Rejects schemes, paths, whitespace, "@", and obviously malformed input.
  VERIFIED_DOMAIN_FORMAT = /\A[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+\z/.freeze

  # Service-provider entity ID / assertion consumer URL. Computed from the
  # organization slug; not stored, so a slug rename transparently updates
  # both metadata and callback URLs.
  def sp_entity_id
    "#{base_url}/saml/metadata/#{organization.slug}"
  end

  def acs_url
    "#{base_url}/users/auth/saml/callback"
  end

  def effective_attribute_mappings
    defaults = {
      "email" => "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress",
      "name"  => "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"
    }
    defaults.merge(attribute_mappings.to_h)
  end

  # Form-friendly accessor that maps a multi-line / comma-separated string
  # onto the underlying `verified_domains` array. Lets us render a textarea
  # in the admin form without fighting Rails' array param handling.
  def verified_domains_text
    Array(verified_domains).join("\n")
  end

  def verified_domains_text=(value)
    self.verified_domains =
      if value.is_a?(Array)
        value
      else
        value.to_s.split(/[\r\n,]+/)
      end
  end

  # Returns true when the email's domain is explicitly in the org's
  # verified_domains allowlist. Used by the JIT provisioner to gate
  # auto-linking against a password-only user with a matching email
  # (cross-org identity-theft protection).
  def email_domain_verified?(email)
    str = email.to_s
    return false unless str.include?("@")
    domain = str.split("@", 2).last.to_s.strip.downcase
    return false if domain.blank?
    Array(verified_domains).include?(domain)
  end

  # L-8: SAML assertion replay protection.
  #
  # SAML assertions are bearer tokens: anyone who captures a valid SAMLResponse
  # (proxy log, browser history on a shared box, a malicious IdP-side actor)
  # can POST it back to our ACS again within its validity window and get a
  # fresh session. Signature checks alone don't stop this -- the captured
  # assertion is still validly signed. The standard mitigation is one-time
  # use: remember each assertion's unique ID until it can no longer be valid,
  # and refuse any assertion whose ID we've already seen.
  #
  # We track the consumed ID in Rails.cache (no DB column / migration). The
  # TTL is the assertion's own validity window plus our allowed clock drift,
  # so the marker outlives every moment the assertion could still be accepted.
  # After that the assertion is rejected by the normal NotOnOrAfter check
  # anyway, so we can let the cache entry expire and reclaim the space.
  #
  # Fails CLOSED: a blank assertion ID (we can't prove uniqueness) and an
  # already-seen ID both return false -> the caller must reject the login.
  # The cache write uses unless_exist so the check-and-set is atomic against
  # concurrent replays of the same assertion landing on two web workers.
  #
  # Caller contract (e.g. Sso::JitProvisioner / the SAML callback): pass the
  # SAML Assertion ID (preferred) or, failing that, the InResponseTo value,
  # and the assertion's validity window in seconds. Treat a falsey return as
  # "replay / unverifiable -- do not sign the user in".
  REPLAY_GUARD_CACHE_NAMESPACE = "saml_assertion_replay".freeze

  # Fallback TTL when the caller can't supply the assertion's NotOnOrAfter
  # window. Generous enough to cover any realistic assertion lifetime so a
  # short fallback never lets a replay slip through after the marker expires.
  DEFAULT_ASSERTION_VALIDITY = 10.minutes

  def consume_assertion!(assertion_id, validity_window: DEFAULT_ASSERTION_VALIDITY)
    id = assertion_id.to_s.strip
    # Fail closed: without a stable unique ID we cannot guarantee one-time use.
    return false if id.blank?

    window = validity_window.respond_to?(:to_i) ? validity_window.to_i : 0
    window = DEFAULT_ASSERTION_VALIDITY.to_i if window <= 0

    # Outlive the assertion's acceptance window by the allowed clock drift so
    # the replay marker can never expire while the assertion is still valid.
    ttl = window + assertion_clock_drift_seconds

    # Namespace by org so an assertion ID from one IdP can't collide with /
    # be consumed by another org's (defense-in-depth; IDs are globally unique
    # in practice but we don't rely on that).
    cache_key = "#{REPLAY_GUARD_CACHE_NAMESPACE}/#{id_for_replay_namespace}/#{id}"

    # Atomic claim: write only if the key does not already exist. A truthy
    # return means WE claimed it (first use, allow). A falsey return means it
    # was already present (replay, deny).
    Rails.cache.write(cache_key, Time.current.to_i, unless_exist: true, expires_in: ttl)
  end

  # Allowed SP/IdP clock drift in seconds, mirrored from to_omniauth_options.
  # Kept as a method so the replay TTL and the SAML validation tolerance stay
  # in lockstep if the tolerance ever changes.
  def assertion_clock_drift_seconds
    30
  end

  # Builds the option hash expected by omniauth-saml. Kept here (rather than
  # in the initializer) so the model owns its SAML wire-level shape.
  def to_omniauth_options
    {
      idp_entity_id: idp_entity_id,
      idp_sso_target_url: idp_sso_target_url,
      idp_slo_target_url: idp_slo_target_url,
      idp_cert: idp_cert,
      name_identifier_format: name_identifier_format,
      sp_entity_id: sp_entity_id,
      assertion_consumer_service_url: acs_url,
      issuer: sp_entity_id,
      attribute_statements: {
        email: Array(effective_attribute_mappings["email"]),
        name:  Array(effective_attribute_mappings["name"])
      },
      security: {
        authn_requests_signed: false,
        want_assertions_signed: true,
        # Standard SaaS default: rely on TLS between SP and IdP as the only
        # encryption layer for assertions. Turning this on would require every
        # customer to provision an SP encryption keypair and upload the public
        # half to their IdP, which is high friction for little gain given that
        # assertions never travel in cleartext off the wire.
        want_assertions_encrypted: false,
        digest_method: "http://www.w3.org/2001/04/xmlenc#sha256",
        signature_method: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
      },
      # 30-second tolerance for clock skew between SP and IdP. Tight enough to
      # keep the replay window small, loose enough to absorb NTP-typical drift
      # without flaking auth on customers whose IdP clock differs by a few
      # seconds.
      allowed_clock_drift: 30
    }
  end

  private

  # Per-config namespace for the replay cache key. Uses the persisted record
  # id when available, falling back to the organization id (a config is always
  # 1:1 with an org). Never blank so two orgs can't share a replay namespace.
  def id_for_replay_namespace
    id.presence || organization_id || "unsaved"
  end

  def base_url
    # Single source of truth: the boot-time initializer at
    # config/initializers/base_url.rb. It raises in production if BASE_URL
    # is unset and supplies a sensible default in dev/test, so we don't
    # repeat the silent fallback here -- doing so would reintroduce the
    # exact misconfig vector the initializer was added to prevent.
    Rails.application.config.x.base_url
  end

  def organization_on_team_plan
    return if organization.blank?
    return if organization.entitlements.sso_enabled?
    errors.add(:base, "SSO requires the Team plan")
  end

  # Parse the cert with OpenSSL so malformed contents surface clearly at save
  # time rather than at SAML auth time (where the error is buried in a gem
  # stack trace). We still check the PEM markers first for a friendlier error
  # on the obvious "user pasted the wrong thing" case.
  def cert_format
    return if idp_cert.blank?

    unless idp_cert.include?("-----BEGIN CERTIFICATE-----") && idp_cert.include?("-----END CERTIFICATE-----")
      errors.add(:idp_cert, "must be a PEM-formatted x509 certificate (include BEGIN/END markers)")
      return
    end

    begin
      OpenSSL::X509::Certificate.new(idp_cert)
    rescue OpenSSL::X509::CertificateError => e
      errors.add(:idp_cert, "is not a valid x509 certificate: #{e.message}")
    end
  end

  # Downcase, strip, dedupe, and drop blanks. Keeps the underlying array
  # canonical so `email_domain_verified?` can do a simple `include?` check
  # without needing to normalize on every read.
  def normalize_verified_domains
    return if verified_domains.nil?
    self.verified_domains = Array(verified_domains)
      .map { |d| d.to_s.strip.downcase }
      .reject(&:blank?)
      .uniq
  end

  def verified_domains_format
    return if verified_domains.blank?
    Array(verified_domains).each do |domain|
      unless domain.is_a?(String) && domain.match?(VERIFIED_DOMAIN_FORMAT)
        errors.add(:verified_domains, "contains an invalid domain: #{domain.inspect}")
      end
    end
  end
end
