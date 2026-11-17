# Cloudflare Turnstile gate for public, unauthenticated form posts.
#
# Included once in ApplicationController so it also covers Devise's stock
# controllers (sessions, unlocks) without generating custom subclasses.
# The callback only fires on POST #create of:
#   - Devise sessions / registrations / passwords / confirmations / unlocks
#   - ContactsController
#
# It is prepended in ApplicationController so it runs BEFORE the app-wide
# callbacks that call `user_signed_in?` — on sessions#create Devise has
# already enabled params authentication by then, so any earlier
# `warden.authenticate?` would check the password (and sign the user in)
# before the captcha is verified.
#
# Controllers can override `turnstile_verification_failed` to customise the
# failure response; the default re-renders the Devise `new` form with 422.
module TurnstileProtection
  extend ActiveSupport::Concern

  TURNSTILE_DEVISE_CONTROLLERS = %w[sessions registrations passwords confirmations unlocks].freeze
  TURNSTILE_FAILURE_MESSAGE = "We couldn't verify that you're human. Please complete the security check and try again.".freeze

  included do
    prepend_before_action :verify_turnstile!, if: :turnstile_protected_action?
  end

  private

  def turnstile_protected_action?
    return false unless action_name == "create" && request.post?

    if devise_controller?
      TURNSTILE_DEVISE_CONTROLLERS.include?(controller_name)
    else
      controller_path == "contacts"
    end
  end

  def verify_turnstile!
    # Already-authenticated users (e.g. Settings → "Verify email" resend)
    # skip the challenge. `warden.authenticated?` reads the session only —
    # it does NOT run the params strategy the way `user_signed_in?` would.
    return if warden.authenticated?(:user)

    result = TurnstileVerifier.new.verify(
      token: params["cf-turnstile-response"].to_s,
      remote_ip: turnstile_remote_ip
    )
    return if result.success?

    Rails.logger.info("[turnstile] rejected #{controller_path}##{action_name}: #{result.error_codes.join(',')}")
    # sessions#create has already called `allow_params_authentication!`;
    # turn it back off so `user_signed_in?` in the re-rendered layout can't
    # authenticate (and sign in) with the submitted email/password.
    request.env["devise.allow_params_authentication"] = false
    turnstile_verification_failed
  end

  # Behind the Cloudflare proxy, request.remote_ip resolves to a Cloudflare
  # edge address (their ranges aren't in trusted_proxies), so prefer the
  # header Cloudflare sets with the real visitor IP. `remoteip` is only an
  # advisory signal to siteverify, so a spoofed header on a direct-to-origin
  # request can't make an invalid token pass.
  def turnstile_remote_ip
    request.headers["CF-Connecting-IP"].presence || request.remote_ip
  end

  def turnstile_verification_failed
    self.resource = resource_class.new(email: params.dig(resource_name, :email).to_s)
    flash.now[:alert] = TURNSTILE_FAILURE_MESSAGE
    render :new, status: :unprocessable_content
  end
end
