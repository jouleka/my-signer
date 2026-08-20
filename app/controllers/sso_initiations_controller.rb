class SsoInitiationsController < ApplicationController
  # Intentionally unauthenticated: the whole point is to initiate SSO login.
  skip_before_action :redirect_to_onboarding_if_needed, raise: false

  # Maximum concurrent in-flight SSO flows per session. Bounds session size
  # and protects against a client opening hundreds of SSO tabs to enlarge
  # the cookie. 3 is plenty for reasonable usage.
  MAX_CONCURRENT_SSO_FLOWS = 3

  # GET /auth/sso?slug=xxx
  #
  # Starts a SAML flow. Each call generates a fresh nonce and records
  # `{nonce => slug}` in the session. The nonce is threaded through SAML
  # RelayState (echoed back by the IdP) so that concurrent tabs don't
  # contaminate each other's flows -- each request's setup proc and
  # callback read their specific slug via the inbound RelayState.
  def new
    slug = params[:slug].to_s.strip.presence
    return render_generic_failure if slug.blank?

    config = SsoConfiguration.joins(:organization).find_by(
      organizations: { slug: slug },
      enabled: true
    )
    return render_generic_failure if config.nil?
    return render_generic_failure unless config.organization.entitlements.sso_enabled?

    nonce = SecureRandom.urlsafe_base64(24)
    store_sso_flow(nonce, slug)
    # Back-compat: also keep the legacy single-slug session key so in-flight
    # callbacks from old browsers without RelayState still resolve. Newer
    # flows always prefer the nonce lookup.
    session["sso_org_slug"] = slug

    @saml_initiation_url = "/users/auth/saml"
    @relay_state_nonce = nonce
    # Use the default application layout; there is no separate devise layout.
    render :new
  end

  private

  def store_sso_flow(nonce, slug)
    flows = (session["sso_flows"] || {}).dup
    flows[nonce] = slug
    # Trim to the newest N entries. Ruby hashes preserve insertion order,
    # so `flows.to_a.last(N)` keeps the most recent ones.
    flows = flows.to_a.last(MAX_CONCURRENT_SSO_FLOWS).to_h
    session["sso_flows"] = flows
  end

  # Never reveal whether the slug matched, exists, or has SSO disabled --
  # single opaque redirect prevents org enumeration via this endpoint.
  def render_generic_failure
    redirect_to new_user_session_path, alert: "SSO is not available. Please sign in with your password or contact your administrator."
  end
end
