# Warden callback that records failed sign-in attempts as audit events on
# every org the user (if identifiable) owns. For each failed attempt we log
# `sign_in_failed` with the attempted email domain in metadata (the raw
# email is sensitive PII we shouldn't persist long-term).
#
# This fires for ALL failed auth paths (wrong password, bad OAuth token,
# failed SAML assertion). Devise's password-based failure includes the
# submitted email in request params; we use that to look up the user.
# Password reset and unlock paths don't end with `failure`, so they're
# not captured here.
Warden::Manager.before_failure do |env, opts|
  next unless opts[:scope] == :user

  request = ActionDispatch::Request.new(env)
  submitted_email = request.params.dig("user", "email").to_s.downcase.strip
  next if submitted_email.blank?

  user = User.find_by(email: submitted_email)
  next if user.nil?

  email_domain = submitted_email.split("@").last

  # Coarse-grained dedup: if we already wrote a sign_in_failed for this
  # email+ip in the last 60 seconds, skip. Bounds the per-failure write
  # amplification when the user owns many orgs (one row per owned org per
  # attempt) AND the attempt-rate amplification during a brute-force spray.
  # The Rack::Attack throttle (5/email/20min, 20/ip/60s) is the real defense;
  # this just tames the audit noise on top of an already-throttled stream.
  #
  # In test env Rails.cache is :null_store so `read` always returns nil and
  # `write` is a no-op -- the dedup degrades to the previous behavior, which
  # keeps existing tests deterministic. In production (memory_store / redis /
  # solid_cache) the dedup actually fires.
  dedup_key = "auth_failure_audit:#{submitted_email}:#{request.ip}"
  next if Rails.cache.read(dedup_key)
  Rails.cache.write(dedup_key, true, expires_in: 60.seconds)

  user.owned_organizations.find_each do |org|
    Audit::Logger.log(
      action: "sign_in_failed",
      actor: user,
      organization: org,
      metadata: { email_domain: email_domain, reason: opts[:message].to_s },
      request: request
    )
  end
rescue => e
  # Never let audit instrumentation affect the auth failure response.
  Rails.logger.error("[auth_failure_audit] #{e.class}: #{e.message}")
end
