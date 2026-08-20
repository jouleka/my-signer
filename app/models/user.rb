class User < ApplicationRecord
# Include default devise modules. Others available are:
# :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
devise :database_authenticatable, :registerable,
       :recoverable, :rememberable, :validatable,
       :confirmable, :lockable, :timeoutable,
       :omniauthable, omniauth_providers: %i[google_oauth2 github apple saml]

  # Deletion cascades:
  # - owned_organizations: Organizations where user is owner get fully deleted with all their data
  # - memberships: User's membership records are deleted (but organizations they don't own remain)
  # - api_tokens: User's API tokens are deleted
  # - sent_invitations: Organization invitations sent by this user are deleted
  has_many :owned_organizations, class_name: "Organization", foreign_key: "owner_id", dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :organizations, through: :memberships
  belongs_to :last_organization, class_name: "Organization", optional: true
  has_many :api_tokens, dependent: :destroy
  has_many :sent_invitations, class_name: "OrganizationInvitation", foreign_key: "inviter_id", dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :billing_subscriptions, dependent: :destroy

  enum :plan_tier, { free: 0, pro: 1, team: 2 }

  # Soft-delete: when a user requests account deletion we mark them with
  # deleted_at and a hashed deletion_token (bytes of opaque entropy), block
  # sign-in, and email them a one-time restoration link. After
  # PendingDeletionPurgeJob::RETENTION_DAYS the row is hard-destroyed,
  # cascading via dependent: :destroy.
  DELETION_TOKEN_BYTES = 32

  scope :pending_deletion, -> { where.not(deleted_at: nil) }
  scope :active_accounts,  -> { where(deleted_at: nil) }

  # Raised by `regenerate_deletion_token!` when the caller invokes it on
  # an active user. A bare RuntimeError would also work but a dedicated
  # class lets callers (rake tasks, admin tooling, future support UI)
  # rescue precisely without swallowing unrelated errors.
  class NotPendingDeletion < StandardError; end

  # Any user destroy (today: only PendingDeletionPurgeJob; tomorrow:
  # potentially admin tooling, fixture cleanup) cascades via
  # `dependent: :destroy` on owned_organizations. The user row's
  # `last_organization_id` FK has no `on_delete:` action (defaults to
  # NO ACTION), so when one of the orgs being deleted is the user's
  # last-viewed org, Postgres raises `foreign_key_violation`. Nilling
  # the column inline is the cheapest fix; `update_column` skips
  # callbacks so we don't recurse into other destroy-time hooks, and
  # runs inside the destroy's transaction so the change rolls back if
  # anything later in the cascade aborts.
  before_destroy :nullify_last_organization_reference

  private def nullify_last_organization_reference
    update_column(:last_organization_id, nil) if last_organization_id.present?
  end
  public

  def deleted?
    deleted_at.present?
  end

  # Marks the user for deletion. Returns the plain-text token that must be
  # emailed to the user; the database stores only its SHA-256 hash so a DB
  # leak alone cannot be used to restore arbitrary deleted accounts.
  #
  # Also revokes every active API token the user owns, so a leaked CLI
  # token cannot continue to authenticate during the 90-day grace window.
  # We deliberately do NOT un-revoke on restore: the user can mint a fresh
  # token from settings if they come back.
  def soft_delete!
    plain_token = nil

    # `with_lock` opens a transaction and `SELECT ... FOR UPDATE`s this
    # row, so a concurrent second call (browser double-submit, retry
    # storm) blocks here until the first one commits. The `deleted?`
    # check is then re-evaluated under the lock, which is the actual
    # idempotency gate -- the unlocked check at the top of the prior
    # version let two callers both pass and both regenerate the
    # deletion_token, silently invalidating the email the first call
    # had already mailed out.
    with_lock do
      return nil if deleted?

      plain_token = SecureRandom.urlsafe_base64(DELETION_TOKEN_BYTES)
      update!(
        deleted_at: Time.current,
        deletion_token: Digest::SHA256.hexdigest(plain_token),
        # Wipe rememberable cookies on every device the user is signed
        # in on. `active_for_authentication?` already blocks the actual
        # sign-in, so this is defense-in-depth -- if a future Devise
        # release ever short-circuits the auto-sign-in-from-cookie
        # before the active_for_authentication? gate, the absent token
        # is the second line of defense.
        remember_created_at: nil
      )
      api_tokens.where(revoked: false).update_all(revoked: true, revoked_at: Time.current)
    end

    # Cancel Paddle subscriptions out of band. We do NOT call Paddle
    # synchronously from the destroy request because Faraday's
    # configured timeout is 20s × up to 4 retries × N subscriptions --
    # a multi-sub user during a Paddle outage would block the web
    # worker for over a minute. The job retries on transient errors
    # (see CancelPaddleSubscriptionsJob); permanent failures surface
    # via Rails.error so support can manually cancel from the error-
    # tracker context. The local soft-delete + restoration token are
    # already committed by this point, so a Paddle-side delay never
    # strands the user in an undeletable state.
    #
    # Wrap in a rescue: if the queue-write itself fails (SolidQueue
    # connection error, schema mismatch), we don't want the whole
    # soft-delete to 500 -- the row is already committed, the user is
    # already locked out, and the email is about to go out. Report and
    # carry on; ops can re-enqueue from rails console using the user
    # ID from the error report.
    if billing_subscriptions.exists?
      begin
        CancelPaddleSubscriptionsJob.perform_later(id)
      rescue StandardError => e
        Rails.logger.error("[soft_delete!] failed to enqueue CancelPaddleSubscriptionsJob for user=#{id}: #{e.class}: #{e.message}")
        Rails.error.report(e, handled: true, severity: :error, context: { user_id: id, action: "soft_delete_paddle_enqueue" })
      end
    end

    plain_token
  end

  def restore!
    return unless deleted?

    transaction do
      update!(deleted_at: nil, deletion_token: nil)

      # Resync plan/trial state with whatever the billing layer says
      # *now* (which may differ from the snapshot we had at soft-delete
      # time -- a Paddle subscription may have been cancelled by
      # soft_delete!, an in-flight trial may have expired during the
      # grace window, or an admin may have changed the user's tier
      # manually). Drives PlanEnforcer to re-apply limits on every
      # owned organization.
      BillingSubscription.recalculate_user_plan!(self)
    end
  end

  # Mints a fresh restoration token without resetting the 90-day countdown.
  # Used by support (or a future "resend my restoration email" path) when
  # the original token never reached the user (e.g. mailer outage). The
  # caller is responsible for emailing the returned plain token.
  #
  # `actor:` is required so the audit trail records WHO regenerated the
  # token, not the user being acted upon. A support flow passes the
  # support agent's User; a future user-initiated "resend" flow passes
  # `self`. Defaulting to `self` would silently misattribute support
  # actions to the deleted user, which would defeat the audit trail's
  # purpose.
  #
  # Records an audit entry on every org the user owns so support actions
  # are not invisible. Today there's no production caller -- this is a
  # support-tooling primitive -- but logging at the model layer means
  # any future caller (rake task, console, admin UI) gets the audit
  # trail for free without having to remember to log it themselves.
  def regenerate_deletion_token!(actor:)
    raise NotPendingDeletion, "user is not pending deletion" unless deleted?

    plain_token = SecureRandom.urlsafe_base64(DELETION_TOKEN_BYTES)
    transaction do
      update!(deletion_token: Digest::SHA256.hexdigest(plain_token))
      owned_organizations.find_each do |org|
        Audit::Logger.log(
          action: "deletion_token_regenerated",
          actor: actor,
          organization: org
        )
      end
    end
    plain_token
  end

  # Looks up a soft-deleted user by the plain-text restoration token. The
  # column stores a SHA-256 hash (see soft_delete!), so we must hash the
  # input before querying. Overrides AR's dynamic `find_by_deletion_token`
  # finder which would otherwise compare the plain input to the stored hash.
  def self.find_by_deletion_token(plain_token)
    return nil if plain_token.blank?

    pending_deletion.find_by(deletion_token: Digest::SHA256.hexdigest(plain_token))
  end

  # Devise integration: soft-deleted accounts cannot authenticate. The flash
  # message key (:pending_deletion) is rendered from
  # config/locales/devise.en.yml under devise.failure.pending_deletion.
  def active_for_authentication?
    super && !deleted?
  end

  def inactive_message
    deleted? ? :pending_deletion : super
  end

  # Devise's :recoverable module is normally orthogonal to
  # `active_for_authentication?` -- a soft-deleted user could still
  # request a password reset and (with inbox access) set a new
  # password during the 90-day grace window. Even though
  # `active_for_authentication?` would still block sign-in afterwards,
  # we don't want to mint a reset token at all for a pending-deletion
  # account. The legitimate path back is the restoration link in the
  # deletion-confirmation email.
  #
  # `Devise.paranoid = true` makes the response copy uniform across
  # known/unknown email lookups, but a determined attacker could still
  # distinguish soft-deleted from active by timing the response (active
  # users incur a token-gen DB write + mailer enqueue; we no-op). The
  # gap is small in practice (single-digit milliseconds) and the
  # soft-deleted state is short-lived (90-day max), so we accept the
  # residual timing oracle rather than absorbing it with fake work.
  def send_reset_password_instructions
    return if deleted?
    super
  end

  scope :email_notifications_enabled, -> { where(email_notifications_enabled: true) }
  scope :certificate_expiry_notifications_enabled, -> { email_notifications_enabled.where(notify_certificate_expiry: true) }
  scope :profile_expiry_notifications_enabled, -> { email_notifications_enabled.where(notify_profile_expiry: true) }
  scope :keystore_expiry_notifications_enabled, -> { email_notifications_enabled.where(notify_keystore_expiry: true) }
  scope :sync_failure_notifications_enabled, -> { email_notifications_enabled.where(notify_sync_failures: true) }
  scope :sync_change_notifications_enabled, -> { email_notifications_enabled.where(notify_sync_changes: true) }
  scope :revocation_notifications_enabled, -> { email_notifications_enabled.where(notify_revocations: true) }
  scope :team_activity_notifications_enabled, -> { email_notifications_enabled.where(notify_team_activity: true) }
  scope :paid_plan, -> { where(plan_tier: plan_tiers.values_at("pro", "team")) }
  scope :on_active_trial, -> {
    where.not(trial_ends_at: nil)
      .where("trial_ends_at > ?", Time.current)
      .where(plan_tier: plan_tiers[:pro])
  }

  # Duration of the automatic reverse trial granted to new signups.
  TRIAL_DURATION = 14.days

  # Virtual attribute backing the registration form's required ToS checkbox.
  # Submitted as "1" when the user ticks the box. Persisted state lives in
  # the `terms_accepted_at` column (set via before_validation below) so we
  # have an audit trail of when consent was given. OmniAuth sign-ups are
  # exempt from this validation -- their acceptance is recorded inside
  # `from_omniauth` when the User row is built.
  attr_accessor :accepts_terms

  validate :password_complexity, if: -> { password.present? }
  validate :terms_must_be_accepted, on: :create, unless: :skip_terms_acceptance_validation?

  before_validation :record_terms_acceptance_timestamp, on: :create

  # Order matters here. Pricing::PlanEnforcer#apply! (invoked by
  # enforce_plan_limits! below) opens `user.with_lock`, which reloads the
  # record and clears dirty-tracking state. If any later after_commit
  # callback consults `saved_change_to_plan_tier`, it will see `nil` and
  # silently no-op. Register plan-tier-dependent hooks BEFORE
  # enforce_plan_limits!; everything else follows after.
  after_commit :handle_plan_tier_change_for_keyword_tracking!, if: :saved_change_to_plan_tier?
  after_commit :enforce_plan_limits!, if: :saved_change_to_plan_tier?
  after_create :start_reverse_trial!, unless: :skip_reverse_trial_on_create?

  # Thread-local opt-out for the reverse-trial callback. Tests set this to
  # true via rails_helper so they create users with the DB-default free plan;
  # specs that need to exercise trial behavior explicitly opt back in.
  # Production code NEVER sets this -- Devise signups always trigger the trial.
  def self.skip_reverse_trial_on_create
    Thread.current[:skip_reverse_trial_on_create] == true
  end

  def self.skip_reverse_trial_on_create=(value)
    Thread.current[:skip_reverse_trial_on_create] = value
  end

  def self.with_reverse_trial(&block)
    previous = Thread.current[:skip_reverse_trial_on_create]
    Thread.current[:skip_reverse_trial_on_create] = false
    yield
  ensure
    Thread.current[:skip_reverse_trial_on_create] = previous
  end

  # Thread-local opt-out for the ToS acceptance validation. Tests set this
  # to true via rails_helper so existing fixtures using `User.create!`
  # without an `accepts_terms` param don't break. Specs that exercise the
  # actual sign-up consent flow opt back in via
  # `User.with_terms_acceptance_validation { ... }` or by setting
  # `User.skip_terms_acceptance_validation = false` for the example.
  # Production code NEVER sets this -- the registration form always
  # submits an explicit acceptance and OmniAuth records its own.
  def self.skip_terms_acceptance_validation
    Thread.current[:skip_terms_acceptance_validation] == true
  end

  def self.skip_terms_acceptance_validation=(value)
    Thread.current[:skip_terms_acceptance_validation] = value
  end

  def self.with_terms_acceptance_validation(&block)
    previous = Thread.current[:skip_terms_acceptance_validation]
    Thread.current[:skip_terms_acceptance_validation] = false
    yield
  ensure
    Thread.current[:skip_terms_acceptance_validation] = previous
  end

  def onboarding_completed?
    onboarding_completed_at.present?
  end

  # True when the user said they ship to a platform during onboarding but the
  # given org still has no active credential for it. Used by the credential
  # controllers to keep the user on the wizard's connect step (instead of
  # bouncing to the org dashboard) when they're catching up on credentials
  # they prematurely "skipped" during onboarding.
  def onboarding_has_pending_platform?(organization)
    return false unless organization
    case onboarding_platform.to_s
    when "ios"
      !organization.app_store_connect_credentials.active.exists?
    when "android"
      !organization.google_play_credentials.active.exists?
    when "both"
      !organization.app_store_connect_credentials.active.exists? ||
        !organization.google_play_credentials.active.exists?
    else
      false
    end
  end

  # NOT memoized on purpose. The same User object can persist across boundaries
  # (Devise/Warden in tests, background-job retries, long-running flows) where
  # `plan_tier` may be mutated via `update_columns` or external admin tooling
  # without firing callbacks. A stale memo there silently grants/denies the
  # wrong limits. Pricing::Entitlements.new is cheap (no DB), so we re-construct
  # on each call and let Organization#entitlements memoize at its own boundary.
  def entitlements
    Pricing::Entitlements.for_user(self)
  end

  def current_billing_subscription
    BillingSubscription.current_for(self)
  end

  def notifications_enabled?
    email_notifications_enabled?
  end

  def notification_lead_time_days
    notification_days_before
  end

  def notify_certificate_expiry?
    notifications_enabled? && super
  end

  def notify_profile_expiry?
    notifications_enabled? && super
  end

  def notify_keystore_expiry?
    notifications_enabled? && super
  end

  def notify_sync_failures?
    notifications_enabled? && super
  end

  def notify_sync_changes?
    notifications_enabled? && super
  end

  def notify_revocations?
    notifications_enabled? && super
  end

  def notify_team_activity?
    notifications_enabled? && super
  end

  def notify_member_activity?
    notifications_enabled? && super
  end

  def notify_api_token_activity?
    notifications_enabled? && super
  end

  def notify_sso_activity?
    notifications_enabled? && super
  end

  def notify_security_alerts?
    notifications_enabled? && super
  end

  def notify_billing_changes?
    notifications_enabled? && super
  end

  def notify_release_activity?
    notifications_enabled? && super
  end

  def notify_audit_digest?
    notifications_enabled? && super
  end

  # Returns true when the user is currently within their 14-day reverse trial
  # window AND has not upgraded to a paid Paddle subscription. A user who
  # upgraded during the trial has their trial fields cleared by
  # BillingSubscription.recalculate_user_plan!, so this returns false for them.
  def on_active_trial?
    trial_ends_at.present? &&
      trial_ends_at > Time.current &&
      pro? &&
      !active_billing_subscription?
  end

  # How many days remain in the active trial. Returns 0 when not on trial.
  # Same-day expirations return 0 (the day we downgrade).
  def trial_days_remaining
    return 0 unless on_active_trial?
    [ (trial_ends_at.to_date - Date.current).to_i, 0 ].max
  end

  # Returns true when the user previously had a trial that has now ended.
  # Used to drive loss-aversion upgrade copy.
  def trial_expired?
    trial_ends_at.present? &&
      trial_ends_at <= Time.current &&
      !active_billing_subscription?
  end

  private

  def enforce_plan_limits!
    Pricing::PlanEnforcer.new(self).apply!
  end

  # Keyword Rank Tracker plan-change handler. Runs on every plan_tier commit
  # and adjusts each owned organization's TrackedKeywordCountry.enabled rows
  # to fit the new tier's `max_tracked_keywords_per_app` limit.
  #
  # Hook choice: this sits on User (not in Billing::Paddle::WebhookProcessor
  # or BillingSubscription.recalculate_user_plan!) because `plan_tier` is
  # authoritative on User and multiple paths mutate it -- Paddle webhooks,
  # TrialExpirationJob, admin tooling. A User-level after_commit catches
  # all of them uniformly without each caller having to remember to fan out.
  # Mirrors the sibling `after_commit :enforce_plan_limits!` already on this
  # model (screenshot-project / org-ownership enforcement).
  #
  # Compares pre-commit and post-commit tier limits to decide direction:
  # smaller limit => prune excess; larger limit => reactivate paused. Equal
  # limits (e.g., an upsell that doesn't touch tracked-keyword allowance) are
  # a no-op. Direction is determined by comparing the per-app max only, not
  # by the pre/post plan index, so future catalog tweaks that bump other
  # entitlements without changing the keyword allowance don't trigger
  # spurious work here.
  def handle_plan_tier_change_for_keyword_tracking!
    old_tier, new_tier = saved_change_to_plan_tier
    return if old_tier.blank? || new_tier.blank? || old_tier == new_tier

    old_max = Pricing::Entitlements.new(old_tier).max_tracked_keywords_per_app
    new_max = Pricing::Entitlements.new(new_tier).max_tracked_keywords_per_app

    return if old_max == new_max

    owned_organizations.find_each do |org|
      # Orgs memoize entitlements keyed by owner plan_tier; force a refresh
      # so the services see the post-commit tier even if the org was
      # touched earlier in this callback chain.
      org.reset_entitlements_memo!

      if new_max < old_max
        Aso::PlanDowngradePruner.call(organization: org)
      elsif new_max > old_max
        Aso::PlanUpgradeReactivator.call(organization: org)
      end
    end
  end

  # Starts a 14-day reverse trial for a newly-created user.
  #
  # Only starts a trial if the user was created with the default "free" tier.
  # If a user was explicitly created with a paid tier (admin-provisioned, test
  # fixture, etc.), we respect that and do NOT override with trial-pro.
  #
  # Re-entry prevention: if this email has already claimed a trial (tracked
  # independently of the User record in TrialHistory), skip. This blocks the
  # "delete account, re-register with same email for fresh trial" loop.
  #
  # Implementation note: uses `update!` (not `update_columns`) so the
  # `after_commit :enforce_plan_limits!` callback fires uniformly. The
  # callback resolves to `Pricing::PlanEnforcer#apply!`, which iterates
  # `user.owned_organizations`. A user that was just created via Devise
  # signup owns no organizations yet, so the enforcer is effectively a
  # no-op here. Letting the callback fire avoids a landmine if entitlement
  # logic ever depends on it firing on every plan_tier change.
  #
  # Note on `trial_started_at`: this field is currently write-only in the
  # production app (set here, cleared by BillingSubscription on Paddle
  # upgrade, and asserted in specs). It is intentionally retained for
  # future analytics work -- specifically cohort analysis pairing trial
  # start vs. `trial_ends_at` to measure trial-to-paid conversion windows
  # and to compute retention curves bucketed by signup week. Do NOT drop
  # the column without reviewing the analytics roadmap; it is cheap to
  # keep and expensive to backfill if dropped.
  def start_reverse_trial!
    return unless plan_tier == "free"
    return if TrialHistory.claimed?(email)

    now = Time.current
    update!(
      plan_tier: self.class.plan_tiers[:pro],
      trial_started_at: now,
      trial_ends_at: now + TRIAL_DURATION
    )

    # Record the claim AFTER the trial fields are set. If the claim write
    # fails the user still has their trial; if the trial write fails the
    # claim is never made. We'd rather err on the side of "user got trial,
    # we lost track" than "user lost trial but we marked it claimed".
    TrialHistory.claim!(email)
  end

  def skip_reverse_trial_on_create?
    self.class.skip_reverse_trial_on_create
  end

  def active_billing_subscription?
    billing_subscriptions.active_for_entitlements.exists?
  end

  # Sets `terms_accepted_at` to "now" when the registration form ticked the
  # `accepts_terms` virtual attr. Idempotent: leaves an already-set timestamp
  # alone (e.g., OmniAuth users that pre-populated it in `from_omniauth`).
  def record_terms_acceptance_timestamp
    return if terms_accepted_at.present?
    return unless ActiveModel::Type::Boolean.new.cast(accepts_terms)

    self.terms_accepted_at = Time.current
  end

  # Email/password sign-ups need a recorded ToS acceptance. OmniAuth signups
  # bypass the form (no chance to tick a box) -- `from_omniauth` records the
  # timestamp directly when it builds the User. Test fixtures/factories that
  # set `terms_accepted_at` directly also pass.
  def terms_must_be_accepted
    return if terms_accepted_at.present?

    errors.add(:accepts_terms, I18n.t("activerecord.errors.models.user.attributes.accepts_terms.required",
                                       default: "must be accepted to create an account"))
  end

  # Skip the ToS validation when this User is being created via an OmniAuth
  # provider (`from_omniauth` is responsible for recording acceptance there)
  # or when tests have opted out via the class-level thread-local switch.
  def skip_terms_acceptance_validation?
    provider.present? || self.class.skip_terms_acceptance_validation
  end

  def password_complexity
    rules = {
      lowercase: /[a-z]/,
      uppercase: /[A-Z]/,
      digit:     /\d/,
      symbol:    /[^A-Za-z0-9]/
    }

    rules.each do |name, regex|
      next if password.match?(regex)
      requirement = I18n.t("activerecord.errors.models.user.password_requirements.#{name}")
      errors.add(:password, I18n.t("activerecord.errors.models.user.attributes.password.missing_complexity", requirement: requirement))
    end

    if email.present? && password.downcase.include?(email.split("@").first.downcase)
      errors.add(:password, I18n.t("activerecord.errors.models.user.attributes.password.contains_email_or_username"))
    end
  end

  def self.from_omniauth(auth)
    info = (auth.info&.to_h || {}).with_indifferent_access

    raw_info_source =
      if auth.extra.respond_to?(:raw_info)
        auth.extra.raw_info
      elsif auth.extra.respond_to?(:[])
        auth.extra[:raw_info] || auth.extra["raw_info"]
      end

    raw_info_hash =
      case raw_info_source
      when nil
        {}
      when Hash
        raw_info_source.with_indifferent_access
      else
        raw_info_source.respond_to?(:to_h) ? raw_info_source.to_h.with_indifferent_access : {}
      end

    id_info_source = raw_info_hash[:id_info]
    id_info =
      case id_info_source
      when nil
        {}
      when Hash
        id_info_source.with_indifferent_access
      else
        id_info_source.respond_to?(:to_h) ? id_info_source.to_h.with_indifferent_access : {}
      end

    user_info_source = raw_info_hash[:user_info]
    user_info =
      case user_info_source
      when nil
        {}
      when Hash
        user_info_source.with_indifferent_access
      else
        user_info_source.respond_to?(:to_h) ? user_info_source.to_h.with_indifferent_access : {}
      end

    email = info[:email].presence || id_info[:email]
    email = email&.downcase

    user = User.find_by(provider: auth.provider, uid: auth.uid)
    email_matched_existing_user = user.nil? && email.present? && User.exists?(email: email)

    display_name = info[:name].presence || [ info[:first_name], info[:last_name] ].compact.join(" ").presence

    if display_name.blank? && user_info.present?
      apple_name_source = user_info[:name]
      apple_name =
        case apple_name_source
        when nil
          {}
        when Hash
          apple_name_source.with_indifferent_access
        else
          apple_name_source.respond_to?(:to_h) ? apple_name_source.to_h.with_indifferent_access : {}
        end

      display_name = [ apple_name[:firstName], apple_name[:lastName] ].compact.join(" ").presence
    end

    display_name ||= email&.split("@")&.first

    avatar_url = info[:image].presence || info[:avatar_url].presence

    boolean_type = ActiveModel::Type::Boolean.new
    verification_sources = [
      info[:verified],
      info[:verified_email],
      info[:email_verified],
      raw_info_hash[:email_verified],
      id_info[:email_verified]
    ].compact

    verified = verification_sources.any? { |value| boolean_type.cast(value) }

    if user
      # Respect lockable: don’t bypass a lock
      return user if user.locked_at.present?

      # Soft-deleted users are in their 90-day grace window. The OmniAuth
      # callback is a public unauthenticated endpoint and the eventual
      # sign-in is already blocked by `active_for_authentication?`, but
      # a frozen-pending-purge row should not be mutated mid-window from
      # a public entry point. Returning here lets the failed sign-in
      # render the `pending_deletion` flash via `inactive_message`.
      return user if user.deleted?

      # `user.provider` and `user.uid` already equal `auth.provider` /
      # `auth.uid` here (that's how `find_by` matched), so back-filling
      # them is a no-op. Display-only fields (name, avatar_url) are
      # benign to refresh from the IdP on each sign-in.
      updates = {}
      updates[:name] = display_name if display_name.present? && user.name.blank?
      updates[:avatar_url] = avatar_url if avatar_url.present? && user.avatar_url.blank?

      user.update(updates) if updates.any?

      # Auto-confirm if the provider says email is verified. Safe in this
      # branch because the user is already (provider, uid)-linked — the
      # IdP's "email_verified" claim is being applied to the same
      # identity that originally completed OAuth.
      if user.confirmed_at.blank? && verified
        user.update(confirmed_at: Time.current)
      end

      user
    elsif email_matched_existing_user
      # SECURITY (CWE-287, CWE-289): An existing user is registered with
      # this email but has no OAuth credentials linked yet. Auto-binding
      # the IdP-asserted (provider, uid) to that row from this public,
      # unauthenticated callback is an account-takeover vector — an
      # attacker who controls an IdP account with the same email
      # (compromised Google, Workspace admin, recycled domain, etc.)
      # would claim the victim's row and gain a session against any
      # owned data, sub, or API token.
      #
      # Refuse the auto-link. The OmniAuth callback should treat a
      # `nil` return here as "this email is already registered; sign in
      # via password, then link OAuth in an authenticated session" —
      # the same trust boundary used by every other "link a second
      # auth factor" flow. A dedicated server-driven OAuth-link UI in
      # settings is the proper home for this functionality (TODO).
      nil
    else
      User.new(
        email: email,
        password: SecureRandom.urlsafe_base64(32),
        name: display_name,
        avatar_url: avatar_url,
        provider: auth.provider,
        uid: auth.uid,
        confirmed_at: (Time.current if verified),
        # Completing the OmniAuth flow constitutes acceptance of the Terms
        # and Privacy. Recording the timestamp here gives the audit trail
        # parity with email/password signups (which record via the form).
        terms_accepted_at: Time.current
      )
    end
  end
end
