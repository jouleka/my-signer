require "net/http"

# Server-side verification of Cloudflare Turnstile tokens.
#
# The widget (app/views/shared/_turnstile.html.erb) posts its token as
# `cf-turnstile-response`; this class exchanges it with Cloudflare's
# siteverify endpoint. Tokens are single-use and expire after 300s.
#
# Keys:
#   TURNSTILE_SITE_KEY   - public widget key. Production falls back to the
#                          mysigner.dev widget key; other envs fall back to
#                          Cloudflare's always-pass test key.
#   TURNSTILE_SECRET_KEY - secret key (ENV first, then
#                          credentials.turnstile.secret_key). Production has
#                          NO fallback: a missing secret fails closed.
#
# In the test env the always-pass test secret is honoured locally (no HTTP
# call), so specs that don't care about Turnstile keep working offline.
# Specs that exercise verification stub `secret_key` and WebMock siteverify.
class TurnstileVerifier
  SITEVERIFY_URL = URI("https://challenges.cloudflare.com/turnstile/v0/siteverify").freeze

  PRODUCTION_SITE_KEY = "0x4AAAAAAGFnopcee6ZSxVIY".freeze
  # Cloudflare's documented dummy keys (always pass, visible widget).
  TEST_SITE_KEY = "1x00000000000000000000AA".freeze
  TEST_SECRET_KEY = "1x0000000000000000000000000000000AA".freeze

  Result = Struct.new(:success, :error_codes, keyword_init: true) do
    def success? = success
  end

  def self.site_key
    ENV["TURNSTILE_SITE_KEY"].presence ||
      (Rails.env.production? ? PRODUCTION_SITE_KEY : TEST_SITE_KEY)
  end

  def self.secret_key
    ENV["TURNSTILE_SECRET_KEY"].presence ||
      Rails.application.credentials.dig(:turnstile, :secret_key).presence ||
      (Rails.env.production? ? nil : TEST_SECRET_KEY)
  end

  def initialize(secret_key: self.class.secret_key)
    @secret_key = secret_key
  end

  def verify(token:, remote_ip: nil)
    if @secret_key.blank?
      Rails.logger.error("[turnstile] TURNSTILE_SECRET_KEY is not configured; rejecting submission")
      return failure("missing-input-secret")
    end

    return Result.new(success: true, error_codes: []) if Rails.env.test? && @secret_key == TEST_SECRET_KEY

    return failure("missing-input-response") if token.blank?
    # Cloudflare caps tokens at 2048 chars; reject oversized input before the round-trip.
    return failure("invalid-input-response") if token.length > 2048

    form = { "secret" => @secret_key, "response" => token }
    form["remoteip"] = remote_ip if remote_ip.present?

    response = Net::HTTP.start(SITEVERIFY_URL.host, SITEVERIFY_URL.port, use_ssl: true, open_timeout: 3, read_timeout: 5) do |http|
      request = Net::HTTP::Post.new(SITEVERIFY_URL)
      request.set_form_data(form)
      http.request(request)
    end

    body = JSON.parse(response.body.to_s)
    Result.new(success: body["success"] == true, error_codes: Array(body["error-codes"]))
  rescue StandardError => e
    # Fail closed: a Cloudflare outage blocks protected forms rather than
    # letting unverified traffic through.
    Rails.logger.error("[turnstile] siteverify request failed: #{e.class}: #{e.message}")
    failure("internal-error")
  end

  private

  def failure(code)
    Result.new(success: false, error_codes: [ code ])
  end
end
