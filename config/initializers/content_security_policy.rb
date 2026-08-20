# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  # Enable a conservative CSP only in production to avoid dev friction.
  next unless Rails.env.production?

  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri    :self
    # Font Awesome (cdnjs) is the only external font origin; explicit allowlist
    # replaces the former `https:` wildcard so a compromised inline script
    # can't pull fonts from attacker-controlled origins.
    policy.font_src    :self, "https://cdnjs.cloudflare.com", :data
    # Sticker/pattern renderers load recolored SVGs through blob URLs. `https:`
    # stays here because user-uploaded screenshots/app icons can come from
    # App Store / Play Store CDNs with unpredictable subdomains.
    policy.img_src     :self, :https, :data, "blob:"
    policy.object_src  :none
    policy.script_src  :self, "'strict-dynamic'", "https://cdn.paddle.com"
    # `unsafe-inline` stays for DaisyUI/Tailwind runtime custom-property
    # styles; cdnjs is explicit for Font Awesome, cdn.paddle.com for the
    # Paddle.js checkout stylesheet. Dropped the `https:` wildcard that
    # previously made CSS-based exfiltration trivial.
    policy.style_src   :self, "https://cdnjs.cloudflare.com", "https://cdn.paddle.com", :unsafe_inline
    # Explicit allowlist — Paddle for billing, Cloudflare Insights for the
    # RUM beacon (report target; same-origin /cdn-cgi/rum also covered by
    # :self). Dropped the `https:` catch-all that let any compromised
    # script exfiltrate to any HTTPS endpoint.
    policy.connect_src :self, "https://*.paddle.com", "https://cloudflareinsights.com"
    policy.frame_src   :self, "https://*.paddle.com", "blob:"
    policy.frame_ancestors :self
    # OmniAuth 302-redirects /users/auth/<provider> to the provider's
    # authorize URL; form-action is re-evaluated against the redirect
    # target, so each IdP origin must be on the allowlist.
    policy.form_action :self,
                       "https://*.paddle.com",
                       "https://accounts.google.com",
                       "https://github.com",
                       "https://appleid.apple.com"
    # Upgrade any stray http:// sub-resources to https:// instead of blocking.
    policy.upgrade_insecure_requests true
    # policy.media_src   :self, :https
    # policy.report_uri "/csp-violation-report-endpoint"
  end

  # Nonces for inline importmap/turbo scripts
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  # To start as report-only, uncomment:
  # config.content_security_policy_report_only = true
end
