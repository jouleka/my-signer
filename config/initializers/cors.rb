# Be sure to restart your server when you modify this file.

# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin AJAX requests.

# Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  # Allow Swagger UI and API clients to make requests
  allow do
    # In production, restrict to known domains via CORS_ALLOWED_ORIGINS env var
    # (comma-separated list, e.g. "https://mysigner.com,https://app.mysigner.com")
    # In development/test, allow all origins for convenience.
    #
    # L-21: FAIL CLOSED in production. The previous fallback to "*" meant that
    # if CORS_ALLOWED_ORIGINS was ever unset (or wiped) in production, the API
    # silently became readable cross-origin by ANY site -- exactly the wrong
    # default for a credential vault. When the var is unset in production we
    # now use an EMPTY allowlist (deny all cross-origin), so a misconfig
    # degrades to "no CORS" rather than "open CORS". Dev/test keep the
    # permissive "*" convenience.
    allowed = if Rails.env.production?
      if ENV["CORS_ALLOWED_ORIGINS"].present?
        ENV["CORS_ALLOWED_ORIGINS"].split(",").map(&:strip).reject(&:blank?)
      else
        []
      end
    else
      "*"
    end

    origins allowed

    resource "/api/*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
      credentials: false,
      max_age: 86400 # 24 hours

    resource "/api/docs/*",
      headers: :any,
      methods: [ :get, :options, :head ],
      credentials: false,
      max_age: 86400
  end
end
