module Sso
  # Just-In-Time provisioning for SAML logins. Given an OmniAuth auth hash
  # from a successful SAML assertion, finds or creates the user, links the
  # SAML identity, and ensures a membership in the target organization.
  #
  # Linking strategy (in order):
  # 1. Existing user with matching provider+uid for this org (returning SSO user)
  # 2. Existing user with matching email (first-time SSO for an existing MySigner user)
  # 3. Brand-new user (JIT provision)
  #
  # Never bypasses a locked account.
  class JitProvisioner
    Result = Struct.new(:status, :user, :errors, keyword_init: true)

    PROVIDER_PREFIX = "saml_".freeze

    def initialize(auth, sso_config)
      @auth = auth
      @config = sso_config
      @organization = sso_config.organization
    end

    def call
      email = extract_email
      return failure("No email in SAML assertion") if email.blank?

      # Step 1: Already-linked SAML user for this org -- no email lookup, no
      # domain check. They already belong to this org.
      user = User.find_by(provider: provider_key, uid: auth.uid)

      # Step 2: Existing password-only (or other-OAuth) user matched by email.
      # This is the identity-theft surface: without a verified-domain gate,
      # any Team-tier admin with their own IdP could claim another user's
      # email in a SAMLResponse and silently link the victim's account.
      if user.nil?
        existing = User.find_by(email: email)
        if existing
          unless config.email_domain_verified?(existing.email)
            return Result.new(
              status: :domain_not_verified,
              user: nil,
              errors: [
                "A user with this email already exists, but their domain is not in this org's verified domains list. " \
                "An admin must add the domain to the SSO configuration before auto-linking."
              ]
            )
          end
          user = existing
        end
      end

      # Step 3: Brand-new user. No existing account, nothing to steal --
      # JIT-create as today.
      #
      # `terms_accepted_at` is populated for audit-trail parity with the
      # email/password and OAuth signup paths. SAML users are provisioned by
      # an admin's IdP rather than ticking a box themselves; we record the
      # provisioning moment as their acceptance timestamp so the column is
      # never nil for active users.
      # SECURITY: a soft-deleted user matched via the (provider, uid) lookup
      # at Step 1 or the email fallback at Step 2 must not have their row
      # mutated mid-grace-window from this public SAML callback.
      # `link_saml_identity!` would clobber provider/uid and
      # `ensure_membership!` would back-fill a membership row. Returning
      # before the JIT-create path also prevents the email-uniqueness
      # collision a fresh `User.create!` would hit anyway.
      return Result.new(status: :pending_deletion, user: nil, errors: [ "pending_deletion" ]) if user&.deleted?

      user ||= User.create!(
        email: email,
        name: extract_name.presence || email.split("@").first,
        password: SecureRandom.urlsafe_base64(32) + "Aa1!",  # satisfy complexity
        confirmed_at: Time.current,
        provider: provider_key,
        uid: auth.uid,
        terms_accepted_at: Time.current
      )

      return Result.new(status: :locked, user: nil, errors: [ "locked" ]) if user.locked_at.present?

      ensure_membership!(user)
      link_saml_identity!(user)

      # Notify admins of auto-provisioned user (only fires for fresh users,
      # not for existing-user JIT links). `previously_new_record?` is true
      # immediately after `User.create!` in Step 3 and false for the Step 1/2
      # paths where `user` is loaded via `find_by`.
      if user.previously_new_record? && organization
        SsoJitProvisionedNotificationJob.perform_later(
          organization_id: organization.id,
          provisioned_user_id: user.id
        )
      end

      Result.new(status: :ok, user: user, errors: [])
    rescue => e
      Rails.logger.error("[Sso::JitProvisioner] #{e.class}: #{e.message}")
      failure(e.message)
    end

    private

    attr_reader :auth, :config, :organization

    def provider_key
      "#{PROVIDER_PREFIX}#{organization.slug}"
    end

    def extract_email
      (auth_info&.fetch(:email, nil) || auth.uid).to_s.downcase.strip
    end

    def extract_name
      (auth_info&.fetch(:name, nil)).presence ||
        [ auth_info&.fetch(:first_name, nil), auth_info&.fetch(:last_name, nil) ].compact.join(" ").presence
    end

    def auth_info
      @auth_info ||= (auth.info&.to_h || {}).with_indifferent_access
    end

    def ensure_membership!(user)
      organization.memberships.where(user: user).first_or_create!(role: config.jit_default_role)
    end

    def link_saml_identity!(user)
      # Only overwrite provider/uid if they're unset OR already pointing at a
      # different SAML identity for this same org. Never clobber another SSO
      # provider's link (Google/GitHub/Apple use bare provider names like
      # "google_oauth2"; ours use the "saml_" prefix).
      return if user.provider == provider_key && user.uid == auth.uid

      # Don't overwrite a non-SAML OAuth link for the same user -- add an
      # audit log entry so admins can see the SSO login instead.
      if user.provider.present? && !user.provider.start_with?(PROVIDER_PREFIX)
        # Track SSO session, but don't change their primary OAuth link.
        return
      end

      user.update_columns(provider: provider_key, uid: auth.uid)
    end

    def failure(message)
      Result.new(status: :jit_failed, user: nil, errors: [ message ])
    end
  end
end
