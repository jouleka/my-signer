# Use a dedicated Redis DB for throttling/ban state
Rack::Attack.cache.store =
  if ENV["REDIS_RACK_ATTACK_URL"].present?
    ActiveSupport::Cache::RedisCacheStore.new(url: ENV["REDIS_RACK_ATTACK_URL"])
  else
    Rails.cache
  end

# Return Retry-After on throttled responses
Rack::Attack.throttled_response_retry_after_header = true

# Basic 429 responder + RateLimit headers
Rack::Attack.throttled_responder = lambda do |req|
  match = req.env["rack.attack.match_data"] || {}
  now   = match[:epoch_time] || Time.now.to_i
  period = match[:period] || 60
  reset = now + (period - now % period)

  # Return JSON for API requests
  if req.path.start_with?("/api/")
    headers = {
      "Content-Type"        => "application/json",
      "RateLimit-Limit"     => match[:limit].to_s,
      "RateLimit-Remaining" => "0",
      "RateLimit-Reset"     => reset.to_s
    }

    body = {
      error: "rate_limit_exceeded",
      message: "Rate limit exceeded. Try again in #{period - now % period} seconds.",
      retry_after: reset
    }.to_json

    [ 429, headers, [ body ] ]
  else
    # Return plain text for web requests
    headers = {
      "Content-Type"        => "text/plain",
      "RateLimit-Limit"     => match[:limit].to_s,
      "RateLimit-Remaining" => "0",
      "RateLimit-Reset"     => reset.to_s
    }

    [ 429, headers, [ "Too Many Requests\n" ] ]
  end
end

# Safelist healthchecks
Rack::Attack.safelist("allow /up health") { |req| req.path == "/up" }

# Helper matchers
def contact_path?(req)       = req.post? && req.path == "/contacts"
def login_path?(req)         = req.post? && req.path == "/users/sign_in"
def signup_path?(req)        = req.post? && req.path == "/users"
def pw_reset_path?(req)      = req.post? && req.path == "/users/password"
def confirm_resend_path?(req)= req.post? && req.path == "/users/confirmation"
def account_restore_path?(req)= (req.get? || req.post?) && req.path == "/account/restore"
def api_sync_path?(req)       = req.post? && req.path.match?(%r{^/api/v1/organizations/\d+/(sync_app_store_connect|sync_google_play|sync)$})
def web_sync_path?(req)       = req.post? && req.path.match?(%r{^/organizations/\d+/(sync|sync_google_play)$})
def onboarding_write_path?(req)
  return false unless req.post? || req.patch? || req.put?
  %w[/onboarding/organization /onboarding/token /onboarding/advance /onboarding/skip].include?(req.path)
end
def trial_cancel_path?(req)   = req.delete? && req.path == "/billing/trial"
# L-5: web route that mints API tokens — POST /organizations/:id/api_tokens
# (resources :api_tokens, only create). Each successful POST generates a
# new long-lived bearer credential, so it must not be free to enumerate.
def api_token_create_path?(req) = req.post? && req.path.match?(%r{\A/organizations/\d+/api_tokens(?:\.\w+)?/?\z})

# Extract email param safely
def normalized_email(req)
  params = req.params rescue {}
  (params["user"] && params["user"]["email"]) || params["email"]
end

# 1) Contact form throttles (prevent spam)
Rack::Attack.throttle("contacts/ip", limit: 5, period: 1.hour) { |req| req.ip if contact_path?(req) }

# 2) Login throttles
Rack::Attack.throttle("logins/ip", limit: 20, period: 60) { |req| req.ip if login_path?(req) }
Rack::Attack.throttle("logins/email", limit: 5, period: 20.minutes) do |req|
  e = normalized_email(req)&.downcase&.strip
  "#{e}" if login_path?(req) && e.present?
end

# 2) Signup throttles
Rack::Attack.throttle("signups/ip", limit: 5, period: 1.hour) { |req| req.ip if signup_path?(req) }

# 3) Password reset throttles
Rack::Attack.throttle("pw_reset/ip", limit: 5, period: 20.minutes) { |req| req.ip if pw_reset_path?(req) }
Rack::Attack.throttle("pw_reset/email", limit: 3, period: 30.minutes) do |req|
  e = normalized_email(req)&.downcase&.strip
  "#{e}" if pw_reset_path?(req) && e.present?
end

# 4) Confirmation resend throttles
Rack::Attack.throttle("confirm_resend/ip", limit: 5, period: 10.minutes) { |req| req.ip if confirm_resend_path?(req) }
Rack::Attack.throttle("confirm_resend/email", limit: 3, period: 15.minutes) do |req|
  e = normalized_email(req)&.downcase&.strip
  "#{e}" if confirm_resend_path?(req) && e.present?
end

# 4a) Account restoration throttle. Each unauthenticated POST runs
# BillingSubscription.recalculate_user_plan! + per-org audit-event writes,
# and even GET issues a SHA-256 hash + indexed lookup. Without this, the
# endpoint is a low-cost amplifier (one request -> N DB writes).
Rack::Attack.throttle("account_restore/ip", limit: 10, period: 15.minutes) { |req| req.ip if account_restore_path?(req) }

# 4b) Per-token throttle on POST /account/restore — defense against
# password brute-force on a single leaked restoration token.
#
# Devise's :lockable counter does NOT increment in this code path.
# `Users::AccountRestorationsController#complete_restore_with_password!`
# calls `@user.valid_password?(submitted)` directly — a bare bcrypt
# compare that bypasses the Warden strategy chain that drives
# :lockable's failed_attempts bookkeeping. Without this throttle the
# per-IP rule above is the only gate, which a distributed attacker
# can bypass.
#
# Keying on the SHA-256 of the submitted token (rather than the raw
# token) keeps the plaintext out of the throttle cache — the same
# defensive reason `users.deletion_token` stores a hash. Limit is
# tighter than the IP rule because legit usage is 1-2 attempts per
# token; 5/15min absorbs typos without giving a brute-forcer a useful
# rate against any single hijacked token.
Rack::Attack.throttle("account_restore_attempts/token", limit: 5, period: 15.minutes) do |req|
  if req.post? && req.path == "/account/restore"
    raw_token = req.params["token"].to_s
    Digest::SHA256.hexdigest(raw_token) if raw_token.present?
  end
end

# 5) Google OAuth2 throttles
if defined?(Rack::Attack)
  Rack::Attack.throttle("oauth/google/authorize/ip", limit: 20, period: 60) { |req|
    req.ip if req.post? && req.path == "/users/auth/google_oauth2"
  }
end

# 5a) SAML SSO endpoints (Team-tier). Rate-limit to prevent:
#   - brute-force probing of org slugs via /auth/sso?slug=X
#   - abuse of the public SAML metadata endpoint
#   - flooding of the IdP callback (cert validation + DB work per hit)
#   - AuthnRequest initiation abuse
Rack::Attack.throttle("sso/initiate/ip", limit: 10, period: 1.minute) do |req|
  req.ip if req.path == "/auth/sso" && (req.get? || req.post?)
end

Rack::Attack.throttle("sso/metadata/ip", limit: 30, period: 1.minute) do |req|
  req.ip if req.get? && req.path.match?(%r{\A/saml/metadata/[a-z0-9][a-z0-9\-]*\z})
end

Rack::Attack.throttle("sso/authn_request/ip", limit: 20, period: 1.minute) do |req|
  req.ip if req.post? && req.path == "/users/auth/saml"
end

Rack::Attack.throttle("sso/callback/ip", limit: 20, period: 1.minute) do |req|
  req.ip if req.post? && req.path == "/users/auth/saml/callback"
end

# 6) Screenshot upload throttles (web routes)
Rack::Attack.throttle("web/screenshot_upload/ip", limit: 5, period: 1.minute) do |req|
  req.ip if req.post? && req.path.match?(%r{/screenshot_projects/\d+/upload_export$})
end

Rack::Attack.throttle("web/screenshot_store_upload/ip", limit: 3, period: 1.minute) do |req|
  req.ip if req.post? && req.path.match?(%r{/screenshot_projects/\d+/start_store_upload$})
end

# 7) API sync endpoint throttle
Rack::Attack.throttle("api/sync/ip", limit: 5, period: 1.minute) do |req|
  req.ip if api_sync_path?(req)
end

# 8) Web sync endpoint throttle
Rack::Attack.throttle("web/sync/ip", limit: 8, period: 1.minute) do |req|
  req.ip if web_sync_path?(req)
end

# 8a) Onboarding write endpoints. These are authenticated but each
# successful POST creates rows (Organization, ApiToken, Membership) or
# advances state. An attacker who has stolen a session cookie could
# otherwise mass-create orgs / tokens at sign-in speed. Per-IP is fine
# here -- this is "burst floor", not "per-user accounting"; legitimate
# onboarding is a handful of requests.
Rack::Attack.throttle("web/onboarding/ip", limit: 30, period: 1.minute) do |req|
  req.ip if onboarding_write_path?(req)
end

# 8b) User-initiated end-of-trial. DELETE /billing/trial drops the
# user to Free immediately and writes plan-tier audit events; an
# attacker with a stolen session could repeatedly toggle
# trial -> Free -> (re-trial via separate flow if it existed). Tight
# per-IP cap keeps this to a few legitimate clicks per hour.
Rack::Attack.throttle("billing/trial_cancel/ip", limit: 5, period: 1.hour) do |req|
  req.ip if trial_cancel_path?(req)
end

# 8c) L-5: API-token minting (web). POST /organizations/:id/api_tokens issues
# a new bearer credential each call. An attacker with a stolen session could
# otherwise mint tokens without bound — each one a fresh, independently
# revocable foothold that survives a password reset. 10/hour per user is
# generous for real usage (tokens are created occasionally, by hand) while
# capping abuse; the per-IP bound catches a coordinated burst from one origin
# and covers the pre-warden edge where no user id is resolved.
Rack::Attack.throttle("web/api_token_create/user", limit: 10, period: 1.hour) do |req|
  req.env["warden"]&.user&.id if api_token_create_path?(req)
end

Rack::Attack.throttle("web/api_token_create/ip", limit: 10, period: 1.hour) do |req|
  req.ip if api_token_create_path?(req)
end

# 9) API rate limiting (token-based)
# Helper to extract API token from Authorization header
def api_token(req)
  auth = req.get_header("HTTP_AUTHORIZATION")
  return nil unless auth&.start_with?("Bearer ")
  auth.split(" ", 2).last
end

# Hash token for cache key to avoid storing raw tokens in Redis
def hashed_api_token(req)
  token = api_token(req)
  return nil unless token.present?
  Digest::SHA256.hexdigest(token)[0, 32]
end

# Helper to check if request is to API
def api_request?(req)
  req.path.start_with?("/api/v1/")
end

# API rate limit by token (100 requests per minute per token)
Rack::Attack.throttle("api/token", limit: 100, period: 1.minute) do |req|
  token_hash = hashed_api_token(req)
  "api-token:#{token_hash}" if api_request?(req) && token_hash.present?
end

# API rate limit by IP (for unauthenticated or invalid token requests)
Rack::Attack.throttle("api/ip", limit: 20, period: 1.minute) do |req|
  req.ip if api_request?(req) && api_token(req).blank?
end

# Higher token-based limit for screenshot exports (high-volume sequential uploads)
Rack::Attack.throttle("api/screenshot_exports/token", limit: 200, period: 1.minute) do |req|
  token_hash = hashed_api_token(req)
  "api-screenshot-exports:#{token_hash}" if api_request?(req) && req.path.include?("/screenshot_exports") && token_hash.present?
end

# Phase 0: credential-read endpoints — tighter than the global 100/min.
# Applies to:
#  /api/v1/organizations/:id/credentials/...
#  /api/v1/organizations/:id/android_keystores (list)
#  /api/v1/organizations/:id/android_keystores/:id/download
#  /api/v1/organizations/:id/android_keystores/:id/secrets
#  /api/v1/organizations/:id/builds/asc_upload/...
#  /api/v1/organizations/:id/profiles/:id/download      (L-3 parity)
#  /api/v1/organizations/:id/certificates/:id/download  (L-3 parity)
#
# L-3: the iOS profile/certificate download endpoints stream the same
# class of signing material as the keystore download above, so they get
# the same credential-read budget rather than the looser global API limit.
# `(?:\.\w+)?` before each end anchor tolerates a routed format suffix
# (e.g. `.json`) — without it, `.../download.json` routes to the same action
# but slips the throttle (Rails appends an optional `(.:format)` to routes).
CREDENTIAL_PATHS_RE = %r{
  ^/api/v1/organizations/\d+/
  (?:
    credentials/                                                       |
    android_keystores(?:/\d+/(?:download|secrets))?(?:\.\w+)?/?$       |
    android_keystores(?:\.\w+)?$                                       |
    builds/asc_upload                                                  |
    (?:profiles|certificates)/\d+/download(?:\.\w+)?/?$
  )
}x

Rack::Attack.throttle("api/credential_read/token", limit: 30, period: 1.minute) do |req|
  if req.path.match?(CREDENTIAL_PATHS_RE)
    hashed_api_token(req)
  end
end

Rack::Attack.throttle("api/credential_read/ip", limit: 60, period: 1.minute) do |req|
  req.ip if req.path.match?(CREDENTIAL_PATHS_RE)
end

# L-2: bulk credential-purge — DELETE /api/v1/organizations/:id/credentials.
# This is the `mysigner logout --purge` route (routes.rb): one call deletes
# every ASC / Google Play / Apple Ads / Android keystore row for the org,
# emitting an audit event per row. The credential-read regex above only
# matches `credentials/` (trailing slash) so the bare destructive endpoint
# slipped through with just the loose global 100/min. Match the destructive
# credentials endpoint(s) — `credentials` with a trailing slash or end —
# and clamp it well below the read budget. Legit purge is a one-shot.
CREDENTIAL_DESTROY_RE = %r{^/api/v1/organizations/\d+/credentials(?:\.\w+|/|$)}

Rack::Attack.throttle("api/credential_destroy/token", limit: 5, period: 1.minute) do |req|
  if req.delete? && req.path.match?(CREDENTIAL_DESTROY_RE)
    hashed_api_token(req)
  end
end

Rack::Attack.throttle("api/credential_destroy/ip", limit: 10, period: 1.minute) do |req|
  req.ip if req.delete? && req.path.match?(CREDENTIAL_DESTROY_RE)
end

# Optional: temporary bans after repeated failed logins (allow2ban)
# This requires detecting a failed sign-in; Devise returns 200 w/ errors.
# If you add a failure marker header or log hook, you can key off it here.
# Example placeholder:
# Rack::Attack.allow2ban("login-fails", threshold: 10, period: 10.minutes, ban_period: 1.hour) do |req|
#   login_path?(req) && req.env["devise.login_failed"] == true
# end

Rack::Attack.throttle("competitor_lookup/user", limit: 10, period: 1.minute) do |req|
  if req.path.end_with?("/keywords/competitor_lookup") && req.post?
    req.env["warden"]&.user&.id
  end
end

Rack::Attack.throttle("competitor_lookup/ip", limit: 20, period: 1.minute) do |req|
  if req.path.end_with?("/keywords/competitor_lookup") && req.post?
    req.ip
  end
end

# /keywords/suggestions proxies to search.itunes.apple.com. The per-term
# Rails.cache (1h) is bypassable by enumerating novel terms, so an
# unthrottled caller could turn a single session into sustained outbound
# traffic to Apple. 60/user/min is comfortable for interactive typing
# (the client debounces) while capping abuse; the IP bound catches
# coordinated sessions from one origin.
Rack::Attack.throttle("keywords_suggestions/user", limit: 60, period: 1.minute) do |req|
  if req.path.end_with?("/keywords/suggestions") && req.get?
    req.env["warden"]&.user&.id
  end
end

Rack::Attack.throttle("keywords_suggestions/ip", limit: 120, period: 1.minute) do |req|
  if req.path.end_with?("/keywords/suggestions") && req.get?
    req.ip
  end
end

# PATCH /organizations/.../keywords/:id/append commits a basket into a
# StoreListing (row lock + audit event). The action is idempotent-noop on
# duplicates but still writes an AuditEvent per call; throttle keeps a
# compromised session from flooding the audit log.
Rack::Attack.throttle("keywords_append/user", limit: 10, period: 1.minute) do |req|
  if req.patch? && req.path.match?(%r{/keywords/[^/]+/append\z})
    req.env["warden"]&.user&.id
  end
end

Rack::Attack.throttle("keywords_append/ip", limit: 20, period: 1.minute) do |req|
  if req.patch? && req.path.match?(%r{/keywords/[^/]+/append\z})
    req.ip
  end
end

# Apple Ads credential writes run ES256 JWT validation against Apple's
# auth endpoint and persist encrypted material — cheap enough one-off,
# expensive if flooded. The route is declared `resource :apple_ads_credential`
# (singular), so the URL is `/apple_ads_credential` with no trailing "s".
# Match the singular form.
Rack::Attack.throttle("apple_ads_credential/user", limit: 5, period: 1.minute) do |req|
  if req.path.end_with?("/apple_ads_credential") && (req.post? || req.put? || req.patch?)
    req.env["warden"]&.user&.id
  end
end

# Saved-keyword-ideas writes an AuditEvent per create/delete. Without a
# throttle a compromised session can pile audit rows faster than the
# retention job prunes them.
Rack::Attack.throttle("saved_keyword_ideas/user", limit: 30, period: 1.minute) do |req|
  if req.path.match?(%r{/saved_keyword_ideas(/.*)?\z}) && (req.post? || req.delete?)
    req.env["warden"]&.user&.id
  end
end

# TrackedKeywords writes an AuditEvent per create/destroy (tracked_keyword_added
# / tracked_keyword_removed). enforce_tracking_limits! caps total keywords per
# app but does nothing to slow cycling add/remove through the audit log.
# Matches both POST /tracked_keywords and DELETE /tracked_keywords/:id.
Rack::Attack.throttle("tracked_keywords/user", limit: 30, period: 1.minute) do |req|
  if req.path.match?(%r{/tracked_keywords(/.*)?\z}) && (req.post? || req.delete?)
    req.env["warden"]&.user&.id
  end
end

if Rails.env.development?
    Rack::Attack.throttle("dev/smoke", limit: 3, period: 10) { |req| req.get? && req.path == "/up" }
end
