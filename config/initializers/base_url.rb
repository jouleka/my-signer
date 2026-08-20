# Centralizes the canonical base URL for the running app. Used by:
#   - SsoConfiguration#sp_entity_id / #acs_url (SAML SP metadata)
#   - SamlMetadataController (XML generation)
#   - Any code that needs absolute URLs outside of a request context (jobs,
#     mailers without a request, etc.)
#
# The `BASE_URL` env var is preferred (deploy-specific). In production, it is
# REQUIRED -- silently falling back to a hardcoded host would emit wrong
# SP entity IDs and ACS URLs in SAML metadata, which would be impossible
# to debug from an IdP-side error and dangerous if deployed to a customer
# subdomain. So we fail loudly at boot instead.
base_url = ENV["BASE_URL"].presence

# Skip the check when assets:precompile runs during the Docker build: the
# Rails-default SECRET_KEY_BASE_DUMMY=1 toggle signals a build-time boot that
# doesn't actually serve traffic, so runtime-only env vars aren't available
# yet. The check still fires on real production boots.
if Rails.env.production? && base_url.blank? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
  raise <<~ERR
    BASE_URL environment variable is required in production.
    SAML SP metadata, ACS URLs, mailer absolute links, and other
    out-of-request URL generators rely on it.
    Set BASE_URL=https://your-domain.example before booting.
  ERR
end

default = case Rails.env
when "test"
  "http://www.example.com"  # rspec-rails default host
else
  "http://localhost:3000"
end

Rails.application.config.x.base_url = base_url || default
