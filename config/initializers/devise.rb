# frozen_string_literal: true

# Assuming you have not yet modified this file, each configuration option below
# is set to its default value. Note that some are commented out while others
# are not: uncommented lines are intended to protect your configuration from
# breaking changes in upgrades (i.e., in the event that future versions of
# Devise change the default values for those options).
#
# Use this hook to configure devise mailer, warden hooks and so forth.
# Many of these configuration options can be set straight in your model.
Devise.setup do |config|
  # The secret key used by Devise. Devise uses this key to generate
  # random tokens. Changing this key will render invalid all existing
  # confirmation, reset password and unlock tokens in the database.
  # Devise will use the `secret_key_base` as its `secret_key`
  # by default. You can change it below and use your own secret key.
  # config.secret_key = ENV.fetch("DEVISE_SECRET_KEY")

  # ==> Controller configuration
  # Configure the parent class to the devise controllers.
  # config.parent_controller = 'DeviseController'

  # ==> Mailer Configuration
  # Configure the e-mail address which will be shown in Devise::Mailer.
  config.mailer_sender = "MySigner <no-reply@mysigner.dev>"

  # Configure the class responsible to send e-mails.
  # config.mailer = 'Devise::Mailer'

  # Configure the parent class responsible to send e-mails.
  config.parent_mailer = "ApplicationMailer"

  # ==> ORM configuration
  # Load and configure the ORM. Supports :active_record (default) and
  # :mongoid (bson_ext recommended) by default. Other ORMs may be
  # available as additional gems.
  require "devise/orm/active_record"

  # ==> Configuration for any authentication mechanism
  # Configure which keys are used when authenticating a user. The default is
  # just :email. You can configure it to use [:username, :subdomain], so for
  # authenticating a user, both parameters are required. Remember that those
  # parameters are used only when authenticating and not when retrieving from
  # session. If you need permissions, you should implement that in a before filter.
  # You can also supply a hash where the value is a boolean determining whether
  # or not authentication should be aborted when the value is not present.
  # config.authentication_keys = [:email]

  # Configure parameters from the request object used for authentication. Each entry
  # given should be a request method and it will automatically be passed to the
  # find_for_authentication method and considered in your model lookup. For instance,
  # if you set :request_keys to [:subdomain], :subdomain will be used on authentication.
  # The same considerations mentioned for authentication_keys also apply to request_keys.
  # config.request_keys = []

  # Configure which authentication keys should be case-insensitive.
  # These keys will be downcased upon creating or modifying a user and when used
  # to authenticate or find a user. Default is :email.
  config.case_insensitive_keys = [ :email ]

  # Configure which authentication keys should have whitespace stripped.
  # These keys will have whitespace before and after removed upon creating or
  # modifying a user and when used to authenticate or find a user. Default is :email.
  config.strip_whitespace_keys = [ :email ]

  # Tell if authentication through request.params is enabled. True by default.
  # It can be set to an array that will enable params authentication only for the
  # given strategies, for example, `config.params_authenticatable = [:database]` will
  # enable it only for database (email + password) authentication.
  # config.params_authenticatable = true

  # Tell if authentication through HTTP Auth is enabled. False by default.
  # It can be set to an array that will enable http authentication only for the
  # given strategies, for example, `config.http_authenticatable = [:database]` will
  # enable it only for database authentication.
  # For API-only applications to support authentication "out-of-the-box", you will likely want to
  # enable this with :database unless you are using a custom strategy.
  # The supported strategies are:
  # :database      = Support basic authentication with authentication key + password
  # config.http_authenticatable = false

  # If 401 status code should be returned for AJAX requests. True by default.
  # config.http_authenticatable_on_xhr = true

  # The realm used in Http Basic Authentication. 'Application' by default.
  # config.http_authentication_realm = 'Application'

  # It will change confirmation, password recovery and other workflows
  # to behave the same regardless if the e-mail provided was right or wrong.
  # Does not affect registerable. Enabling this hides "is this email
  # registered?" oracles on confirmation resend, password reset, and
  # unlock — useful against credential-stuffing reconnaissance even
  # though our locale strings already use "if your email exists" copy.
  config.paranoid = true

  # By default Devise will store the user in session. You can skip storage for
  # particular strategies by setting this option.
  # Notice that if you are skipping storage for all authentication paths, you
  # may want to disable generating routes to Devise's sessions controller by
  # passing skip: :sessions to `devise_for` in your config/routes.rb
  config.skip_session_storage = [ :http_auth ]

  # By default, Devise cleans up the CSRF token on authentication to
  # avoid CSRF token fixation attacks. This means that, when using AJAX
  # requests for sign in and sign up, you need to get a new CSRF token
  # from the server. You can disable this option at your own risk.
  # config.clean_up_csrf_token_on_authentication = true

  # When false, Devise will not attempt to reload routes on eager load.
  # This can reduce the time taken to boot the app but if your application
  # requires the Devise mappings to be loaded during boot time the application
  # won't boot properly.
  # config.reload_routes = true

  # ==> Configuration for :database_authenticatable
  # For bcrypt, this is the cost for hashing the password and defaults to 12. If
  # using other algorithms, it sets how many times you want the password to be hashed.
  # The number of stretches used for generating the hashed password are stored
  # with the hashed password. This allows you to change the stretches without
  # invalidating existing passwords.
  #
  # Limiting the stretches to just one in testing will increase the performance of
  # your test suite dramatically. However, it is STRONGLY RECOMMENDED to not use
  # a value less than 10 in other environments. Note that, for bcrypt (the default
  # algorithm), the cost increases exponentially with the number of stretches (e.g.
  # a value of 20 is already extremely slow: approx. 60 seconds for 1 calculation).
  config.stretches = Rails.env.test? ? 1 : 12

  # Set up a pepper to generate the hashed password.
  # config.pepper = 'f1119823e9e096cf3213e769db849618a4410cd638340349cf85033b7fc0b23edd9db901b78836854d3391f79afee0b6b8a3861b3b4463b105dc14b61981b517'

  # Send a notification to the original email when the user's email is changed.
  # config.send_email_changed_notification = false

  # Send a notification email when the user's password is changed.
  # config.send_password_change_notification = false

  # ==> Configuration for :confirmable
  # A period that the user is allowed to access the website even without
  # confirming their account. For instance, if set to 2.days, the user will be
  # able to access the website for two days without confirming their account,
  # access will be blocked just in the third day.
  # You can also set it to nil, which will allow the user to access the website
  # without confirming their account.
  # Default is 0.days, meaning the user cannot access the website without
  # confirming their account.
  config.allow_unconfirmed_access_for = 0.days

  # A period that the user is allowed to confirm their account before their
  # token becomes invalid. For example, if set to 3.days, the user can confirm
  # their account within 3 days after the mail was sent, but on the fourth day
  # their account can't be confirmed with the token any more.
  # Default is nil, meaning there is no restriction on how long a user can take
  # before confirming their account.
  #
  # L-9: confirmation links must expire. A token that never ages out is a
  # standing account-takeover surface if a confirmation email is later
  # exposed (forwarded inbox, log leak, shared device). 3 days is long
  # enough for a real user to act on the email; a stale link past that
  # window is rejected and the user re-requests confirmation.
  config.confirm_within = 3.days

  # If true, requires any email changes to be confirmed (exactly the same way as
  # initial account confirmation) to be applied. Requires additional unconfirmed_email
  # db field (see migrations). Until confirmed, new email is stored in
  # unconfirmed_email column, and copied to email column on successful confirmation.
  config.reconfirmable = true

  # Defines which key will be used when confirming an account
  # config.confirmation_keys = [:email]

  # ==> Configuration for :rememberable
  # The time the user will be remembered without asking for credentials again.
  config.remember_for = 2.weeks

  # Invalidates all the remember me tokens when the user signs out.
  config.expire_all_remember_me_on_sign_out = true

  # If true, extends the user's remember period when remembered via cookie.
  # config.extend_remember_period = false

  # Options to be passed to the created cookie. For instance, you can set
  # secure: true in order to force SSL only cookies.
  # config.rememberable_options = {}

  # ==> Configuration for :validatable
  # Range for password length.
  config.password_length = 12..128

  # Email regex used to validate email formats. It simply asserts that
  # one (and only one) @ exists in the given string. This is mainly
  # to give user feedback and not to assert the e-mail validity.
  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/

  # ==> Configuration for :timeoutable
  # The time you want to timeout the user session without activity. After this
  # time the user will be asked for credentials again. Default is 30 minutes.
  #
  # L-7: this is a credential vault. An idle authenticated session left open
  # on a shared/unlocked machine is a direct path to the customer's signing
  # secrets. Expire sessions after 2 hours of inactivity so a walked-away
  # session can't be resumed indefinitely. (Timeoutable needs no DB column;
  # last-request time is tracked in the session.)
  config.timeout_in = 2.hours

  # ==> Configuration for :lockable
  # Defines which strategy will be used to lock an account.
  # :failed_attempts = Locks an account after a number of failed attempts to sign in.
  # :none            = No lock strategy. You should handle locking by yourself.
  # Lock after N failed attempts
  config.lock_strategy = :failed_attempts
  config.maximum_attempts = 10
  config.last_attempt_warning = true

  # Defines which key will be used when locking and unlocking an account
  # config.unlock_keys = [:email]

  # Defines which strategy will be used to unlock an account.
  # :email = Sends an unlock link to the user email
  # :time  = Re-enables login after a certain amount of time (see :unlock_in below)
  # :both  = Enables both strategies
  # :none  = No unlock strategy. You should handle unlocking by yourself.
  # Unlock via email link and/or time window
  config.unlock_strategy = :both
  config.unlock_in = 1.hour

  # Number of authentication tries before locking an account if lock_strategy
  # is failed attempts.
  # config.maximum_attempts = 20

  # Time interval to unlock the account if :time is enabled as unlock_strategy.
  # config.unlock_in = 1.hour

  # Warn on the last attempt before the account is locked.
  # config.last_attempt_warning = true

  # ==> Configuration for :recoverable
  #
  # Defines which key will be used when recovering the password for an account
  # config.reset_password_keys = [:email]

  # Time interval you can reset your password with a reset password key.
  # Don't put a too small interval or your users won't have the time to
  # change their passwords.
  config.reset_password_within = 6.hours

  # When set to false, does not sign a user in automatically after their password is
  # reset. Defaults to true, so a user is signed in automatically after a reset.
  # config.sign_in_after_reset_password = true

  # ==> Configuration for :encryptable
  # Allow you to use another hashing or encryption algorithm besides bcrypt (default).
  # You can use :sha1, :sha512 or algorithms from others authentication tools as
  # :clearance_sha1, :authlogic_sha512 (then you should set stretches above to 20
  # for default behavior) and :restful_authentication_sha1 (then you should set
  # stretches to 10, and copy REST_AUTH_SITE_KEY to pepper).
  #
  # Require the `devise-encryptable` gem when using anything other than bcrypt
  # config.encryptor = :sha512

  # ==> Scopes configuration
  # Turn scoped views on. Before rendering "sessions/new", it will first check for
  # "users/sessions/new". It's turned off by default because it's slower if you
  # are using only default views.
  # config.scoped_views = false

  # Configure the default scope given to Warden. By default it's the first
  # devise role declared in your routes (usually :user).
  # config.default_scope = :user

  # Set this configuration to false if you want /users/sign_out to sign out
  # only the current scope. By default, Devise signs out all scopes.
  # config.sign_out_all_scopes = true

  # ==> Navigation configuration
  # Lists the formats that should be treated as navigational. Formats like
  # :html should redirect to the sign in page when the user does not have
  # access, but formats like :xml or :json, should return 401.
  #
  # If you have any extra navigational formats, like :iphone or :mobile, you
  # should add them to the navigational formats lists.
  #
  # The "*/*" below is required to match Internet Explorer requests.
  # config.navigational_formats = ['*/*', :html, :turbo_stream]

  # The default HTTP method used to sign out a resource. Default is :delete.
  config.sign_out_via = :delete

  # ==> OmniAuth
  # Provider credentials come from Rails credentials with ENV fallbacks for
  # development. In the TEST environment we fall back to harmless placeholders
  # so the OAuth strategy MIDDLEWARE is always mounted — OmniAuth test-mode
  # mocking then drives the callbacks. Without a mounted strategy the callback
  # route still exists (declared on the User model) but omniauth.auth is never
  # populated, so OAuth callback tests crash with `undefined method 'provider'
  # for nil` on CI, which has no real client id/secret. The placeholder value
  # is never used for a real request because test mode mocks the provider.
  oauth_cred = ->(value) { value.presence || (Rails.env.test? ? "test-oauth-placeholder" : nil) }

  # Add Google OAuth2 provider.
  google_client_id     = oauth_cred.call(Rails.application.credentials.dig(:google, :client_id)     || ENV["GOOGLE_CLIENT_ID"])
  google_client_secret = oauth_cred.call(Rails.application.credentials.dig(:google, :client_secret) || ENV["GOOGLE_CLIENT_SECRET"])

  if google_client_id.present? && google_client_secret.present?
    config.omniauth :google_oauth2,
      google_client_id,
      google_client_secret,
      scope: "email,profile",
      prompt: "consent",
      access_type: "online"
  end

  github_client_id     = oauth_cred.call(Rails.application.credentials.dig(:github, :client_id)     || ENV["GITHUB_CLIENT_ID"])
  github_client_secret = oauth_cred.call(Rails.application.credentials.dig(:github, :client_secret) || ENV["GITHUB_CLIENT_SECRET"])
  if github_client_id.present? && github_client_secret.present?
    config.omniauth :github,
      github_client_id,
      github_client_secret,
      scope: "user:email"
  end

  apple_service_id  = Rails.application.credentials.dig(:apple, :service_id)  || ENV["APPLE_SERVICE_ID"]
  apple_team_id     = Rails.application.credentials.dig(:apple, :team_id)     || ENV["APPLE_TEAM_ID"]
  apple_key_id      = Rails.application.credentials.dig(:apple, :key_id)      || ENV["APPLE_KEY_ID"]
  apple_private_key = Rails.application.credentials.dig(:apple, :private_key) || ENV["APPLE_PRIVATE_KEY"]
  apple_redirect_uri = Rails.application.credentials.dig(:apple, :redirect_uri) || ENV["APPLE_REDIRECT_URI"]
  apple_additional_client_ids = Rails.application.credentials.dig(:apple, :additional_client_ids) || ENV["APPLE_ADDITIONAL_CLIENT_IDS"]

  if [ apple_service_id, apple_team_id, apple_key_id, apple_private_key ].all?(&:present?)
    sanitized_key = apple_private_key.gsub("\r", "").gsub("\\n", "\n").strip

    apple_options = {
      scope: "name email",
      team_id: apple_team_id,
      key_id: apple_key_id,
      pem: sanitized_key,
      provider_ignores_state: true,
      nonce: :local
    }

    if apple_redirect_uri.present?
      apple_options[:redirect_uri] = apple_redirect_uri
    end

    if apple_additional_client_ids.present?
      apple_options[:authorized_client_ids] = Array(apple_additional_client_ids)
        .flat_map { |value| value.to_s.split(",") }
        .map(&:strip)
        .reject(&:blank?)
    end

    config.omniauth :apple, apple_service_id, apple_options
  end

  # SAML 2.0 SSO for Team-tier orgs. We register the strategy once with
  # placeholder values; a setup: proc loads the org-specific settings from
  # `SsoConfiguration` at auth time, based on a slug stored in the session.
  #
  # The placeholders never actually participate in an auth flow: a production
  # call always goes through SsoInitiationsController which writes the slug
  # into the session before the Rack middleware sees the request.
  config.omniauth :saml,
    idp_entity_id: "sso-configured-per-org",
    idp_sso_target_url: "https://placeholder.invalid/sso",
    name_identifier_format: "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress",
    sp_entity_id: "placeholder",
    issuer: "placeholder",
    assertion_consumer_service_url: "placeholder",
    security: { want_assertions_signed: true },
    setup: ->(env) {
      session = env["rack.session"]
      next if session.nil?

      # Prefer nonce-based lookup via RelayState (protects against concurrent
      # SSO flows in different tabs cross-contaminating). Fall back to the
      # legacy single-slug key for in-flight old flows.
      request = Rack::Request.new(env)
      nonce = request.params["RelayState"].to_s
      slug = if nonce.present?
               (session["sso_flows"] || {})[nonce]
      end
      slug ||= session["sso_org_slug"]
      next if slug.blank?

      config = SsoConfiguration.joins(:organization).find_by(
        organizations: { slug: slug },
        enabled: true
      )
      next if config.nil?
      # Only honor the config if the org is still on Team plan. A downgrade
      # disables SSO even if the SsoConfiguration record still has enabled=true.
      next unless config.organization.entitlements.sso_enabled?

      strategy = env["omniauth.strategy"]
      strategy.options.merge!(config.to_omniauth_options)
      strategy.options[:org_slug] = slug
      strategy.options[:sso_nonce] = nonce if nonce.present?
    }

  # ==> Warden configuration
  # If you want to use other strategies, that are not supported by Devise, or
  # change the failure app, you can configure them inside the config.warden block.
  #
  # config.warden do |manager|
  #   manager.intercept_401 = false
  #   manager.default_strategies(scope: :user).unshift :some_external_strategy
  # end

  # ==> Mountable engine configurations
  # When using Devise inside an engine, let's call it `MyEngine`, and this engine
  # is mountable, there are some extra configurations to be taken into account.
  # The following options are available, assuming the engine is mounted as:
  #
  #     mount MyEngine, at: '/my_engine'
  #
  # The router that invoked `devise_for`, in the example above, would be:
  # config.router_name = :my_engine
  #
  # When using OmniAuth, Devise cannot automatically set OmniAuth path,
  # so you need to do it manually. For the users scope, it would be:
  # config.omniauth_path_prefix = '/my_engine/users/auth'

  # ==> Hotwire/Turbo configuration
  # When using Devise with Hotwire/Turbo, the http status for error responses
  # and some redirects must match the following. The default in Devise for existing
  # apps is `200 OK` and `302 Found` respectively, but new apps are generated with
  # these new defaults that match Hotwire/Turbo behavior.
  # Note: These might become the new default in future versions of Devise.
  config.responder.error_status = :unprocessable_content
  config.responder.redirect_status = :see_other

  # ==> Configuration for :registerable

  # When set to false, does not sign a user in automatically after their password is
  # changed. Defaults to true, so a user is signed in automatically after changing a password.
  # config.sign_in_after_change_password = true
end
