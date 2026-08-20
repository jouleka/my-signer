class Users::ConfirmationsController < Devise::ConfirmationsController
  # GET /resource/confirmation?confirmation_token=abcdef
  # Devise default confirms and signs in only if sign_in_after_change_password etc.
  # We override to: confirm the user, sign them in, then run our after_sign_in_path_for
  def show
    self.resource = resource_class.confirm_by_token(params[:confirmation_token])

    if resource.errors.empty?
      # Soft-deleted users must not get the "confirmed!" success UX,
      # even briefly. `sign_in` here would seat the user in Warden's
      # session without re-running `active_for_authentication?`, so the
      # success flash + post-sign-in redirect would render before the
      # next request bounces them out. That's a usable account-existence
      # oracle: an attacker holding a confirmation token (e.g. forwarded
      # email, mailbox archive) could distinguish "soft-deleted" from
      # "active" rows by which response they get. Match the generic
      # invalid-token copy so neither state is identifiable.
      if resource.respond_to?(:deleted?) && resource.deleted?
        redirect_to new_session_path(resource_name),
          alert: I18n.t("devise.failure.invalid", authentication_keys: "email")
        return
      end

      # Auto sign-in after confirmation to avoid extra login step
      sign_in(resource_name, resource)
      set_flash_message!(:notice, :confirmed)
      respond_with_navigational(resource) { redirect_to after_sign_in_path_for(resource) }
    else
      respond_with_navigational(resource.errors, status: :unprocessable_content) { redirect_to new_session_path(resource_name), alert: resource.errors.full_messages.to_sentence }
    end
  end

  protected

  # When the resend was triggered from the post-signup "check your inbox"
  # page, return the user there (not to sign-in) so they keep the visual
  # context — the same page they were on, now with a "📧 sent" flash. We
  # also refresh the session-stored email in case they corrected a typo
  # via the form on the resend page.
  def after_resending_confirmation_instructions_path_for(resource_name)
    if params[:return_to] == "check_email"
      submitted_email = params.dig(resource_name, :email).presence
      session[:signup_pending_email] = submitted_email if submitted_email
      signup_check_email_path
    else
      super
    end
  end
end
