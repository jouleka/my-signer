class SamlMetadataController < ApplicationController
  # This controller intentionally does NOT require authentication. IdPs fetch
  # metadata anonymously as part of auto-configuration. We guard access by
  # only returning metadata for enabled SSO configs.
  skip_before_action :redirect_to_onboarding_if_needed, raise: false

  # GET /saml/metadata/:slug
  #
  # Returns SP metadata XML that IdPs consume for auto-configuration. This is
  # a public endpoint (IdPs need to fetch it without authentication) but only
  # returns data for orgs with active SSO configurations.
  def show
    org = Organization.find_by(slug: params[:slug])
    config = org&.sso_configuration
    # Gate on entitlement too: a downgrade from Team leaves the record behind
    # with `enabled=true`. Initiation/callback paths already check this; mirror
    # that gate here so a stale config doesn't keep advertising SP metadata.
    if config.nil? || !config.enabled? || !org.entitlements.sso_enabled?
      render plain: "SSO not configured", status: :not_found
      return
    end

    require "onelogin/ruby-saml"
    settings = OneLogin::RubySaml::Settings.new(config.to_omniauth_options)
    meta = OneLogin::RubySaml::Metadata.new
    render xml: meta.generate(settings, true), content_type: "application/samlmetadata+xml"
  end
end
