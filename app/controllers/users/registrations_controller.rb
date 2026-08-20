class Users::RegistrationsController < Devise::RegistrationsController
  before_action :configure_sign_up_params, only: [ :create ]
  before_action :configure_account_update_params, only: [ :update ]

  def destroy
    current_password = params[:current_password]

    unless current_password.present? && resource.valid_password?(current_password)
      prepare_settings_page_data
      @open_settings_modal = "delete_account_modal"
      @delete_account_error = current_password.blank? ? "Password is required" : "Invalid password"

      respond_with resource do |format|
        format.html { render "settings/show", status: :unprocessable_content }
      end
      return
    end

    mailer_failed = false
    plain_token = resource.soft_delete!
    if plain_token.present?
      deletes_at = (resource.deleted_at + PendingDeletionPurgeJob::RETENTION_DAYS.days).to_date

      # `deliver_now` deliberately. `deliver_later` would serialize the
      # plain restoration token into `solid_queue_jobs.arguments` until
      # the worker picks it up, defeating the purpose of storing only a
      # SHA-256 hash on the User row. SMTP failure here is recoverable
      # via `User#regenerate_deletion_token!` (audited) so we accept the
      # in-request mailer cost.
      #
      # Wrap in a rescue: SMTP failure mid-request would otherwise 500
      # while the user is already soft-deleted (committed by
      # `soft_delete!`). Surface a flash so the user knows the deletion
      # took effect but the email didn't, and they need to contact
      # support to regenerate the token. We deliberately do NOT roll
      # back the soft-delete -- the user explicitly asked to be deleted
      # and we already revoked their API tokens, so leaving them in a
      # half-state is worse than telling them about the email failure.
      begin
        BillingMailer.account_pending_deletion(
          user: resource,
          restore_token: plain_token,
          deletes_at: deletes_at
        ).deliver_now
      rescue StandardError => e
        mailer_failed = true
        Rails.logger.error("[registrations#destroy] account_pending_deletion deliver_now failed for user=#{resource.id}: #{e.class}: #{e.message}")
        Rails.error.report(e, handled: true, severity: :error, context: { user_id: resource.id, action: "account_pending_deletion_mailer" })
      end

      # Audit per owned org so each org's audit log shows the
      # soft-delete event for its owner. Mirrors the per-org fan-out
      # pattern used elsewhere (BillingSubscription.log_plan_transition_audit).
      # Also notify any co-members of those orgs in the same loop so they
      # have the full 90-day grace window to export their data before the
      # cascade fires (per Privacy §8 commitment).
      #
      # Co-member notice intentionally bypasses
      # `notify_team_activity?` / `email_notifications_enabled?`. This
      # is a transactional notice tied to a contractual commitment
      # (Privacy §8) -- the co-member's data will be hard-deleted in
      # 90 days through no action of their own. They cannot opt out of
      # being told that. If we ever introduce a "transactional
      # notifications" preference distinct from marketing, revisit.
      # `find_each` rebatches via DB queries so the outer `includes` is
      # discarded; `each` here keeps the bounded collection in memory
      # (orgs-per-user is realistically <10) and the inner co-member
      # queries below batch on their own. Dropping `includes(:users)`
      # because the inner `org.users.where.not(...)` issues its own
      # filtered query that wouldn't reuse a preloaded association
      # anyway.
      resource.owned_organizations.each do |org|
        Audit::Logger.log(
          action: "account_soft_deleted",
          actor: resource,
          organization: org,
          metadata: { deletes_at: deletes_at },
          request: request
        )

        org.users.where.not(id: resource.id).find_each do |co_member|
          BillingMailer.org_owner_pending_deletion(
            co_member: co_member,
            owner: resource,
            organization: org,
            deletes_at: deletes_at
          ).deliver_later

          Audit::Logger.log(
            action: "owner_soft_deleted_co_member_notified",
            actor: resource,
            organization: org,
            metadata: { co_member_user_id: co_member.id, deletes_at: deletes_at },
            request: request
          )
        end
      end
    end

    Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name)
    if mailer_failed
      # Override the success flash so the user knows the deletion took
      # effect but the restoration link didn't reach them. Support can
      # mint a fresh token via `User#regenerate_deletion_token!`.
      flash[:alert] = "Your account was scheduled for deletion, but we couldn't send the restoration email. Contact support to receive a new restoration link."
    else
      set_flash_message! :notice, :destroyed
    end
    yield resource if block_given?
    respond_with_navigational(resource) { redirect_to after_sign_out_path_for(resource_name) }
  end

  # GET /users/sign_up/check_email
  # Dedicated post-signup landing page. Replaces Devise's default
  # behavior of redirecting unconfirmed signups to the public landing
  # (which felt like a dead-end). The email shown is read from the
  # session value set by `after_inactive_sign_up_path_for`; if the
  # session is empty (deep-linked, browser restart, etc.) we still
  # render the page with generic copy.
  def check_email
    @signup_email = session[:signup_pending_email].presence
  end

  def update
    self.resource = resource_class.to_adapter.get!(send(:"current_#{resource_name}").to_key)
    update_params = account_update_params
    prev_unconfirmed_email = resource.unconfirmed_email if resource.respond_to?(:unconfirmed_email)
    # Capture what's changing BEFORE the update so we can emit the right audit
    # event(s) only when the update actually succeeds.
    password_was_set = update_params[:password].present?
    prev_email_value = resource.email
    email_will_change = update_params[:email].present? && update_params[:email] != prev_email_value

    resource_updated = update_resource(resource, update_params)
    yield resource if block_given?

    if resource_updated
      log_account_audit_events!(password_was_set: password_was_set, email_will_change: email_will_change, prev_email: prev_email_value)

      set_flash_message_for_update(resource, prev_unconfirmed_email)
      bypass_sign_in(resource, scope: resource_name) if sign_in_after_change_password?
      respond_with resource, location: after_update_path_for(resource)
    else
      clean_up_passwords resource
      set_minimum_password_length
      prepare_settings_page_data
      @open_settings_modal = settings_modal_from_params(update_params)

      respond_with resource do |format|
        format.html { render "settings/show", status: :unprocessable_content }
      end
    end
  end

  protected

  # Permit the two consent fields we render on the sign-up form:
  # - `accepts_terms` is a virtual attr on User; the model promotes its truthy
  #   value into a `terms_accepted_at` timestamp via before_validation.
  # - `marketing_emails_opt_in` is a real column (default: false).
  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :accepts_terms, :marketing_emails_opt_in ])
  end

  def configure_account_update_params
    devise_parameter_sanitizer.permit(:account_update, keys: [ :name, :provider, :uid, :avatar_url ])
  end

  def update_resource(resource, params)
    # SECURITY: provider/uid can only be cleared via this form (the SSO
    # disconnect modal in settings/show.html.erb submits both as blank).
    # Setting them to a specific value would let any logged-in attacker
    # hijack a victim's OAuth account by claiming the victim's
    # (provider, uid) pair, since `User.from_omniauth` resolves logins
    # by `find_by(provider:, uid:)`. Provider linking must go through a
    # dedicated server-driven OAuth flow that re-verifies upstream
    # account possession.
    if params[:provider].present? || params[:uid].present?
      params = params.except(:provider, :uid)
    end

    email_changed = params[:email] != resource.email
    password_changing = params[:password].present?

    if !email_changed && !password_changing
      resource.update_without_password(params.except(:current_password))
    else
      resource.update_with_password(params)
    end
  end

  def after_update_path_for(_resource)
    settings_path
  end

  # Override Devise's post-signup-but-unconfirmed redirect. Stash the
  # email in the session so the dedicated page can echo it back to the
  # user ("we sent a link to <foo@bar.com>") without putting the email
  # in the URL.
  def after_inactive_sign_up_path_for(resource)
    session[:signup_pending_email] = resource.email
    signup_check_email_path
  end

  private

  # Emit per-org audit events for account changes. We record on every org
  # the user owns (so each org's audit log shows security-relevant changes
  # for its owner). Emails for change events do NOT include the raw new
  # value in metadata -- just "changed" -- to avoid reflecting PII into
  # long-term audit records beyond what's already on the User row.
  def log_account_audit_events!(password_was_set:, email_will_change:, prev_email:)
    return if resource.owned_organizations.none?

    resource.owned_organizations.find_each do |org|
      if password_was_set
        Audit::Logger.log(
          action: "password_changed",
          actor: resource,
          organization: org,
          request: request
        )
      end

      if email_will_change
        Audit::Logger.log(
          action: "email_changed",
          actor: resource,
          organization: org,
          metadata: { previous_email_domain: prev_email.to_s.split("@").last },
          request: request
        )
      end
    end
  end

  def prepare_settings_page_data
    @user = resource
    @api_tokens = resource.api_tokens.order(created_at: :desc)
    @memberships = resource.memberships.includes(:organization).order(created_at: :desc)
  end

  def settings_modal_from_params(params)
    return "disconnect_sso_modal" if disconnecting_sso?(params)
    return "change_password_modal" if params[:password].present? || params[:password_confirmation].present?

    "edit_profile_modal"
  end

  def disconnecting_sso?(params)
    persisted_provider = resource.respond_to?(:provider_was) ? (resource.provider_was.presence || resource.provider) : resource.provider
    params.key?(:provider) && params[:provider].blank? && persisted_provider.present?
  end
end
