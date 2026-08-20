# SSO enforcement: when a user who is a member of an org with enforced SSO
# tries to sign in via password, log them out and redirect back to the
# sign-in page with an :sso_required flash. The user can then navigate to
# /auth/sso?slug=<org-slug> to start the SAML flow.
#
# Break-glass: the org OWNER can always sign in with password, even on an
# enforced-SSO org. This prevents lockout when the IdP is misconfigured or
# the cert expires.
#
# The `after_authentication` hook fires after Devise has accepted the
# credentials but before the session cookie is set. By throwing :warden,
# Devise's failure app runs and redirects to the sign-in page.

Warden::Manager.after_authentication do |user, auth, opts|
  # Only enforce for the user scope
  next unless opts[:scope] == :user
  # CRITICAL: Only skip enforcement for SAML callbacks specifically. Skipping
  # for ALL omniauth callbacks (the earlier implementation) would let users
  # bypass SSO by signing in via Google/GitHub/Apple OAuth. We must block
  # those paths too -- SSO enforcement means SSO-only.
  strategy_name = auth.env["omniauth.strategy"]&.name.to_s
  next if strategy_name == "saml"

  # Skip API token auth (doesn't go through Devise sign-in)
  next if opts[:store] == false

  enforced_orgs = user.organizations.joins(:sso_configuration)
                      .where(sso_configurations: { enabled: true, enforced: true })
  next if enforced_orgs.empty?

  # SECURITY (M-3): evaluate EVERY enforcing org the user belongs to, not an
  # arbitrary `.first`. `Sso::JitProvisioner#link_saml_identity!` writes
  # provider = "saml_<org.slug>", so a user's single persisted provider names
  # exactly ONE org's SAML link. A user who is a member of two enforcing orgs
  # but SAML-linked to only one must STILL be blocked from password login by
  # the other. For each enforcing org the session is "satisfied" only if the
  # org isn't actually enforcing on its current plan (not Team), OR the user is
  # its owner (break-glass), OR the user's persisted provider is THAT org's
  # SAML link. Block if ANY enforcing org is unsatisfied.
  #
  # (The persisted-provider check is also a belt-and-suspenders fallback for
  # env["omniauth.strategy"], which is not reliably set during Warden's
  # after_authentication phase in all Devise/OmniAuth versions.)
  must_block = enforced_orgs.any? do |org|
    org.entitlements.sso_enabled? &&
      org.owner_id != user.id &&
      user.provider.to_s != "saml_#{org.slug}"
  end
  next unless must_block

  # SECURITY-CRITICAL: actually log the user out.
  #
  # `auth.logout` takes a SCOPE symbol, not a user object. Calling
  # `auth.logout(user)` is a no-op (it looks up @users[user_object] which
  # is never set). The correct call is `auth.logout(:user)` or bare
  # `auth.logout` (which defaults to all scopes).
  #
  # If this is wrong, the warden.user.user.key stays in the session and
  # the "blocked" user is actually authenticated -- they just saw a
  # redirect to sign-in but their cookie has a live session. Hitting any
  # authenticated page after the bounce would succeed. This is exactly
  # the SSO-bypass bug that the enforcement is supposed to prevent.
  auth.logout(:user)

  # Belt-and-suspenders: even if Warden's logout misbehaves under a future
  # gem upgrade, explicitly kill the session keys that authenticate the
  # user.
  session = auth.env["rack.session"]
  if session
    session.delete("warden.user.user.key")
    session.delete("warden.user.user.session")
  end

  throw :warden, scope: :user, message: :sso_required
end
