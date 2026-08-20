class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  # Only skip CSRF for Apple (form_post response mode), SAML (IdP POST-back),
  # and the failure redirect.
  skip_before_action :verify_authenticity_token, only: [ :apple, :saml, :failure ]

  def github
    handle_oauth("GitHub")
  end

  def google_oauth2
    handle_oauth("Google")
  end

  def apple
    handle_oauth("Apple")
  end

  # SAML 2.0 callback. Invoked by the IdP after the user authenticates.
  # The slug is resolved via RelayState (preferred, binds to this specific
  # in-flight flow) or falls back to the legacy session["sso_org_slug"] for
  # pre-nonce in-flight flows.
  def saml
    auth = request.env["omniauth.auth"]

    # RelayState is echoed by the IdP. It binds this specific SAML response
    # to the slug that initiated the AuthnRequest, preventing cross-tab
    # contamination. The setup: proc in devise.rb sets :sso_nonce on
    # strategy options when it resolves via RelayState.
    strategy_options = request.env["omniauth.strategy"]&.options || {}
    slug = strategy_options[:org_slug]
    nonce = strategy_options[:sso_nonce] || params["RelayState"].to_s

    # Fall back to legacy single-slug session key if RelayState wasn't used.
    if slug.blank?
      slug = (session["sso_flows"] || {})[nonce] if nonce.present?
      slug ||= session["sso_org_slug"]
    end

    # Clean up session state regardless of outcome.
    if nonce.present? && session["sso_flows"].is_a?(Hash)
      session["sso_flows"] = session["sso_flows"].except(nonce)
    end
    session.delete("sso_org_slug")

    config = SsoConfiguration.joins(:organization).find_by(
      organizations: { slug: slug },
      enabled: true
    )

    if config.nil?
      Rails.logger.warn("[SAML callback] no config for slug=#{slug.inspect}")
      redirect_to new_user_session_path, alert: "SSO configuration not found."
      return
    end

    unless config.organization.entitlements.sso_enabled?
      redirect_to new_user_session_path, alert: "SSO is not available on this organization's plan."
      return
    end

    # SAML assertion replay protection (CWE-294, one-time use). Enforced only
    # when the IdP response surfaces a stable assertion identifier; when none
    # is available (e.g. a strategy that doesn't expose the response object)
    # we proceed rather than block a legitimate login — so this can only ever
    # make auth stricter, never break it. consume_assertion! is an atomic
    # check-and-set: falsey means the assertion ID was already used.
    assertion_id = saml_assertion_id(auth)
    if assertion_id.present? && !config.consume_assertion!(assertion_id)
      Audit::Logger.log(
        action: "sso_login_failed",
        organization: config.organization,
        metadata: { reason: "assertion_replay" },
        request: request
      )
      Rails.logger.warn("[SAML callback] assertion replay rejected slug=#{slug.inspect}")
      redirect_to new_user_session_path, alert: "Could not sign you in via SSO. Contact your administrator."
      return
    end

    result = Sso::JitProvisioner.new(auth, config).call

    case result.status
    when :ok
      Audit::Logger.log(
        action: "sso_login",
        actor: result.user,
        organization: config.organization,
        metadata: { jit: false },
        request: request
      )
      # CWE-384 (session fixation) defense: invalidate any pre-auth session ID
      # before we issue a post-auth session for the SAML user. Devise does this
      # automatically for password auth but NOT for OmniAuth callbacks.
      #
      # The SAML nonce/slug keys (sso_flows, sso_org_slug) have already been
      # consumed above, before the provisioner runs — there is no in-flight
      # SAML state to preserve. But a pending org-invitation handoff CAN live
      # across the SAML flow (user clicks invite link → forced through SSO →
      # invite accepted post-auth), so we explicitly preserve that token.
      pending_invite_token = session.delete(:pending_invite_token)
      reset_session
      session[:pending_invite_token] = pending_invite_token if pending_invite_token
      sign_in_and_redirect result.user, event: :authentication
      set_flash_message(:notice, :success, kind: "SSO") if is_navigational_format?
    when :locked
      redirect_to new_user_session_path, alert: I18n.t("devise.omniauth_callbacks.account_locked")
    when :pending_deletion
      # Soft-deleted user matched in JIT provisioning. Do NOT mutate the
      # row mid-grace-window. Show the generic SSO failure to avoid
      # confirming "this email exists but is being deleted" to an attacker
      # probing via SAMLResponse.
      redirect_to new_user_session_path,
        alert: "Could not sign you in via SSO. Contact your administrator."
    when :domain_not_verified
      # Cross-org identity-theft defense: the IdP asserted an email that
      # matches an existing MySigner user, but the email's domain is not in
      # this org's verified_domains allowlist. Log the specific reason for
      # the admin in the audit row, but show the generic SSO failure message
      # to the user -- a distinct message here would let an attacker probe
      # which emails are existing MySigner accounts by comparing messages.
      Audit::Logger.log(
        action: "sso_login_failed",
        organization: config.organization,
        metadata: {
          reason: "domain_not_verified",
          errors: Array(result.errors).map { |e| e.to_s.truncate(200) },
          email_domain: safe_email_domain(auth.info&.email)
        },
        request: request
      )
      Rails.logger.warn("[SAML callback] domain_not_verified: #{result.errors.inspect}")
      redirect_to new_user_session_path,
        alert: "Could not sign you in via SSO. Contact your administrator."
    when :jit_failed
      Audit::Logger.log(
        action: "sso_login_failed",
        organization: config.organization,
        metadata: {
          errors: Array(result.errors).map { |e| e.to_s.truncate(200) },
          email_domain: safe_email_domain(auth.info&.email)
        },
        request: request
      )
      Rails.logger.error("[SAML callback] JIT failed: #{result.errors.inspect}")
      redirect_to new_user_session_path, alert: "Could not sign you in via SSO. Contact your administrator."
    end
  rescue => e
    Rails.logger.error("[SAML callback] error: #{e.class} #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    redirect_to new_user_session_path, alert: "SSO login failed. Please try again."
  end

  def failure
    redirect_to new_user_session_path, alert: I18n.t("devise.omniauth_callbacks.oauth_failed")
  end

  private
  def handle_oauth(kind)
    auth = request.env["omniauth.auth"]

    # M2 account-restoration round-trip: the user kicked off OAuth from
    # `Users::AccountRestorationsController#update`, which stashed the
    # deletion token + initiation timestamp in session before redirecting
    # here. Cross-check the IdP-asserted (provider, uid) against the
    # soft-deleted row before finalizing the restore. Both session keys
    # are consumed (deleted) on entry so a subsequent normal sign-in
    # can't accidentally re-trigger this branch with a stale token.
    restoration_token = session.delete(:account_restoration_token)
    initiated_at = session.delete(:account_restoration_initiated_at)
    if restoration_token.present?
      handle_account_restoration(auth, kind, restoration_token, initiated_at)
      return
    end

    user = User.from_omniauth(auth)

    # `nil` means User.from_omniauth refused the auto-link: an existing
    # account with this email is registered without OAuth credentials,
    # and binding via this public callback would be an account-takeover
    # surface. Direct the caller to the password sign-in flow; once
    # signed in they can link OAuth via an authenticated settings flow.
    if user.nil?
      redirect_to new_user_session_path,
        alert: "An account with this email is already registered. Sign in with your password, then link #{kind} from your account settings."
      return
    end

    if user.locked_at.present?
      redirect_to new_user_session_path, alert: I18n.t("devise.omniauth_callbacks.account_locked")
      return
    end

    if user.persisted? || user.save
      if user.confirmed?
        sign_in_and_redirect user, event: :authentication
        set_flash_message(:notice, :success, kind: kind) if is_navigational_format?
      else
        user.send_confirmation_instructions
        redirect_to new_user_session_path, notice: I18n.t("devise.omniauth_callbacks.confirmation_sent", email: user.email)
      end
    else
      redirect_to new_user_session_path, alert: user.errors.full_messages.to_sentence
    end
  rescue OmniAuth::Strategies::OAuth2::CallbackError => error
    Rails.logger.warn("#{kind} OAuth callback failed: #{error.error_reason || error.message}")
    redirect_to new_user_session_path, alert: I18n.t("devise.omniauth_callbacks.oauth_failed")
  end

  # Maximum age for an in-flight OAuth restoration round-trip. A real
  # provider hop (Google, GitHub, Apple) takes seconds; 15 minutes
  # absorbs slow networks, MFA prompts, and a moment of "wait, was
  # that my password?" hesitation. Beyond that, the cursor is treated
  # as abandoned to keep a stolen session cookie from quietly completing
  # a long-stale restoration flow.
  ACCOUNT_RESTORATION_FLOW_TTL = 15.minutes

  # Account-restoration round-trip handler. Verifies the IdP-asserted
  # (provider, uid) matches the soft-deleted user pinned by the
  # in-session token, then calls `restore!`, audits, rotates session,
  # and signs the user in. Generic failure messages everywhere — never
  # confirms whether the token, user, or IdP mismatch was the failure
  # cause to an attacker who has half the inputs.
  def handle_account_restoration(auth, kind, token, initiated_at)
    initiated = Time.zone.at(initiated_at.to_i) rescue nil
    if initiated.nil? || initiated < ACCOUNT_RESTORATION_FLOW_TTL.ago
      redirect_to new_user_session_path, alert: "Restoration link is invalid or expired."
      return
    end

    user = User.find_by_deletion_token(token)

    if user.nil? || user.deleted_at.nil?
      redirect_to new_user_session_path, alert: "Restoration link is invalid or expired."
      return
    end

    if user.deleted_at < PendingDeletionPurgeJob::RETENTION_DAYS.days.ago
      redirect_to new_user_session_path, alert: "Restoration link is invalid or expired."
      return
    end

    # The IdP returned a (provider, uid) — verify it matches the row we
    # think we're restoring. Without this check, an attacker who has
    # the restore link could go through *their own* IdP account and
    # restore-and-takeover the victim's row.
    unless user.provider == auth.provider && user.uid == auth.uid
      Rails.logger.warn(
        "[restore via OAuth] (provider, uid) mismatch user_id=#{user.id} " \
        "expected=(#{user.provider}, #{user.uid}) got=(#{auth.provider}, #{auth.uid})"
      )
      redirect_to new_user_session_path,
        alert: "We couldn't verify your identity via #{kind}. Sign in to the same #{kind} account that owns this MySigner account."
      return
    end

    user.restore!

    user.owned_organizations.find_each do |org|
      Audit::Logger.log(
        action: "account_restored",
        actor: user,
        organization: org,
        request: request
      )
    end

    sign_out current_user if user_signed_in?
    reset_session
    sign_in(user)
    redirect_to authenticated_root_path,
      notice: "Welcome back. Your account has been restored."
  end

  # Best-effort extraction of a stable, unique-per-assertion identifier from the
  # OmniAuth SAML response, for replay detection. Prefers the assertion ID, then
  # InResponseTo (both per-assertion). Returns nil when none is available (e.g.
  # test mocks or strategies that don't surface the response object) so the
  # caller skips replay enforcement rather than blocking a legitimate login.
  def saml_assertion_id(auth)
    extra = auth&.extra
    return nil if extra.blank?

    response = extra.respond_to?(:response_object) ? extra.response_object : nil
    candidate = nil
    candidate ||= response.assertion_id if response.respond_to?(:assertion_id)
    # NOTE: only per-assertion identifiers are used. session_index is NOT
    # per-assertion (an IdP may reuse it across re-logins in a session), so
    # using it as a replay key could false-positive-block a legitimate
    # re-login within the TTL. Assertion ID (preferred) / InResponseTo only.
    candidate ||= response.in_response_to if response.respond_to?(:in_response_to)
    candidate.presence
  rescue StandardError => e
    Rails.logger.warn("[SAML callback] could not extract assertion id: #{e.class} #{e.message}")
    nil
  end

  # Returns the domain portion of an email ONLY when the input is clearly
  # well-formed. Prevents malformed IdP-supplied values (e.g., no "@") from
  # landing in audit metadata as raw attacker-controlled identifiers.
  def safe_email_domain(raw)
    str = raw.to_s
    return nil unless str.include?("@")
    domain = str.split("@", 2).last
    domain.present? ? domain.downcase : nil
  end
end
