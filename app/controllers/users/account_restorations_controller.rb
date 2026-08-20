class Users::AccountRestorationsController < ApplicationController
  # Public endpoint: invoked from the one-time link in the
  # account-pending-deletion email. The user clicking the link may be a
  # different person who is currently signed in (shared computer, or
  # the account owner now using a different login). The session is
  # rotated inside `update` (after the token is validated) so a stray
  # GET from a cross-site `<img src>` doesn't sign visitors out --
  # GETs must be safe (CWE-352-ish hygiene). Sign-out happens only on
  # the action path that actually performs the restoration.
  skip_before_action :authenticate_user!, raise: false
  # The restore page must be reachable regardless of who is signed in
  # and what state THEIR account is in. Without these skips, a
  # currently-signed-in visitor whose own account hasn't completed
  # onboarding (or whose plan access is out of sync) gets redirected
  # away by ApplicationController's filters before the action body
  # runs -- the soft-deleted owner's restore link silently no-ops,
  # leaving them stuck. The session swap to the restored user happens
  # inside `update` itself.
  skip_before_action :ensure_current_user_plan_access!, raise: false
  skip_before_action :redirect_to_onboarding_if_needed, raise: false
  before_action :load_user_by_token
  before_action :set_no_store_and_no_referrer

  # GET /account/restore?token=...
  def show
    case @restore_state
    when :missing, :unknown
      render :not_found, status: :not_found
    when :expired
      render :expired, status: :gone
    when :ok
      render :show
    end
  end

  # OAuth providers that this controller can hand off to for the
  # restoration round-trip. SAML JIT users (provider starts with
  # `saml_`) are intentionally excluded — the SAML dance requires
  # org-slug context the controller can't synthesize from the
  # restoration link alone, and self-service SAML restore is rare
  # enough that a "contact your admin" path is acceptable.
  OAUTH_RESTORE_PROVIDERS = %w[google_oauth2 github apple].freeze

  # POST /account/restore?token=...
  def update
    case @restore_state
    when :missing, :unknown
      render :not_found, status: :not_found
    when :expired
      render :expired, status: :gone
    when :ok
      # M2: re-auth required before restore. Possessing the URL alone
      # MUST NOT grant a session against the deleted user's data, paid
      # subs, API tokens, or owned orgs. The link's 90-day TTL plus
      # realistic leak channels (forwarded mailbox, mailbox archives,
      # screenshots in support tickets) make bearer-only auth
      # unacceptable.
      if @user.provider.blank?
        # Email/password user: verify their current password.
        complete_restore_with_password!
      elsif OAUTH_RESTORE_PROVIDERS.include?(@user.provider)
        # OAuth-linked user: kick off a fresh round-trip to the same
        # provider. The callback (`OmniauthCallbacksController#handle_oauth`)
        # consumes `session[:account_restoration_token]` and cross-checks
        # the IdP-asserted (provider, uid) against the soft-deleted row
        # before calling `restore!`. The `_initiated_at` companion key
        # is the staleness gate: an abandoned IdP detour shouldn't leave
        # a long-lived restoration cursor in the session that a session-
        # cookie thief could later complete (they'd also need to control
        # the same IdP account, but defense-in-depth is cheap).
        session[:account_restoration_token] = params[:token].to_s
        session[:account_restoration_initiated_at] = Time.current.to_i
        redirect_to "/users/auth/#{@user.provider}", allow_other_host: false
      else
        # SAML JIT or any other provider — no self-service restore path.
        flash.now[:alert] = "Your account uses a single sign-on provider that requires admin assistance to restore. Contact your administrator or support."
        render :show, status: :unprocessable_content
      end
    end
  end

  private

  def complete_restore_with_password!
    submitted = params[:current_password].to_s
    if submitted.blank? || !@user.valid_password?(submitted)
      # Devise paranoid mode is on globally for the public-facing flows;
      # match the same intent here -- don't disclose whether a password
      # was even submitted vs. submitted-and-wrong, since the only viewer
      # at this point is either the legitimate owner (re-typing) or an
      # attacker who has the token but not the password.
      flash.now[:alert] = "Incorrect password. Please try again."
      render :show, status: :unprocessable_content
      return
    end

    finalize_restore!(@user)
  end

  # Common post-verification path: clears soft-delete state, audits per
  # owned org, rotates the session, signs the user in, redirects. Used by
  # both the password path here and the OAuth round-trip path in
  # `OmniauthCallbacksController#handle_oauth`.
  def finalize_restore!(user)
    user.restore!

    user.owned_organizations.find_each do |org|
      Audit::Logger.log(
        action: "account_restored",
        actor: user,
        organization: org,
        request: request
      )
    end

    # Rotate the Rack session ID across the auth boundary. `sign_out`
    # clears Devise/Warden state but leaves the session cookie value
    # intact, which is the textbook session-fixation surface
    # (CWE-384). The SAML callback at
    # users/omniauth_callbacks_controller.rb does the same dance for
    # the same reason. Order: sign out current (if any) → reset →
    # sign in restored user.
    sign_out current_user if user_signed_in?
    reset_session
    sign_in(user)
    flash[:notice] = "Welcome back. Your account has been restored."
    redirect_to after_restore_path
  end

  # The restoration page carries a single-use token in the URL. Make sure
  # no intermediate cache (browser, proxy, LB) keeps a copy, and don't
  # leak the token to any cross-origin sub-resource via the Referer
  # header. `no-referrer` is stricter than the site-wide meta-policy and
  # is set per-action because this is the only page where we hand the
  # caller a sensitive query-string token.
  def set_no_store_and_no_referrer
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
    response.headers["Referrer-Policy"] = "no-referrer"
  end

  def load_user_by_token
    token = params[:token].to_s
    if token.blank?
      @restore_state = :missing
      return
    end

    @user = User.find_by_deletion_token(token)
    if @user.nil?
      @restore_state = :unknown
    elsif @user.deleted_at < PendingDeletionPurgeJob::RETENTION_DAYS.days.ago
      # Boundary mirrors PendingDeletionPurgeJob#still_eligible? exactly
      # (both use strict `<`), so a user is :expired here precisely when
      # the purge job considers them eligible for deletion. The expiry
      # template has a copy line documenting "90 days" and clicking after
      # the boundary correctly shows :expired without race against the
      # daily purge run -- the user is still in the DB until the next
      # purge tick, but already past the published restore window.
      @restore_state = :expired
    else
      @restore_state = :ok
    end
  end

  def after_restore_path
    # `authenticated_root` is the post-sign-in landing page in this app
    # (see config/routes.rb). Fall back to "/" if for any reason it
    # cannot be resolved.
    main_app.authenticated_root_path
  rescue NoMethodError
    "/"
  end
end
