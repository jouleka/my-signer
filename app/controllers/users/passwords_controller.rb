class Users::PasswordsController < Devise::PasswordsController
  # PATCH /users/password
  #
  # Closes a delayed-takeover oracle on the password-reset path. Devise's
  # default flow calls `reset_password_by_token` (which writes the new
  # password) and then unconditionally `sign_in(resource_name, resource)`
  # regardless of `active_for_authentication?`. For a soft-deleted user
  # that produces two problems:
  #
  #   1. Oracle: the success flash branches on
  #      `resource.active_for_authentication?` — soft-deleted rows get
  #      `:updated_not_active`, active rows get `:updated`. The visible
  #      response shape distinguishes the two states for any caller
  #      holding a valid reset token.
  #
  #   2. Delayed takeover: the bcrypt write succeeds before the response
  #      branches. An attacker with a leaked reset token (mailbox access,
  #      forwarded email, archive grab) can set a password on a row that
  #      is "pending purge". If the legitimate owner later restores the
  #      account inside the 90-day window, the attacker now holds working
  #      credentials.
  #
  # `User#send_reset_password_instructions` already refuses to mint NEW
  # tokens for soft-deleted users. This override closes the residual gap
  # for tokens that were minted BEFORE the soft-delete (Devise's
  # `reset_password_within` default is 6h, plenty of overlap with a
  # delete that happens mid-reset-flow).
  #
  # We resolve the user from the submitted token via Devise's own
  # `with_reset_password_token` (which also handles expiry), check
  # `deleted?`, and short-circuit to the same generic "invalid or expired
  # token" UX that an unknown / stale token would produce — no
  # account-state leak.
  def update
    raw_token = resource_params[:reset_password_token].to_s
    resolved = raw_token.present? ? resource_class.with_reset_password_token(raw_token) : nil

    if resolved&.deleted?
      # Render the SAME shape Devise produces for an unknown / expired
      # token: 422 with a :reset_password_token error rendered into
      # `devise/passwords/edit`. Anything more bespoke (redirect with
      # custom flash) would be a differential the attacker could use
      # to distinguish "this token is for a soft-deleted account" from
      # "this token is garbage". Matching Devise's own invalid-token
      # response collapses the two states into one.
      #
      # Devise's `reset_password_by_token` re-assigns the original
      # plain token onto the returned resource (so the form's hidden
      # `reset_password_token` field round-trips to the user). We
      # mirror that here -- otherwise the form HTML would render an
      # empty hidden field for soft-deleted-with-valid-token while
      # garbage-token would render the user-supplied string, which is
      # exactly the differential we set out to eliminate.
      self.resource = resource_class.new
      resource.reset_password_token = raw_token
      resource.errors.add(:reset_password_token, :invalid)
      set_minimum_password_length
      respond_with(resource, status: :unprocessable_content)
      return
    end

    super
  end
end
