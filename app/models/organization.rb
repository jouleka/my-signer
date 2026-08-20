class Organization < ApplicationRecord
  attribute :access_state, :string, default: "active"
  attribute :access_blocked_at, :datetime
  attribute :access_block_reason, :string
  attribute :access_blocked_by_plan_tier, :string

  belongs_to :owner, class_name: "User"
  has_many :memberships, dependent: :delete_all
  has_many :users, through: :memberships
  has_many :organization_users, class_name: "Membership", dependent: :destroy
  has_many :app_store_connect_credentials, dependent: :destroy
  has_many :google_play_credentials, dependent: :destroy
  has_one :apple_ads_credential, dependent: :destroy
  has_many :organization_invitations, dependent: :destroy
  has_many :apple_certificates, dependent: :destroy
  has_many :apple_devices, dependent: :destroy
  has_many :apple_provisioning_profiles, dependent: :destroy
  has_many :apple_bundle_ids, dependent: :destroy
  has_many :api_tokens, dependent: :destroy
  has_many :android_keystores, dependent: :destroy
  has_many :android_apps, dependent: :destroy
  has_many :android_builds, dependent: :destroy
  has_many :apple_apps, dependent: :destroy
  has_many :apple_builds, dependent: :destroy
  has_many :asc_build_uploads, dependent: :restrict_with_exception
  has_many :app_store_versions, dependent: :destroy
  has_many :testflight_beta_groups, dependent: :destroy
  has_many :apple_merchant_ids, dependent: :destroy
  has_many :apple_app_groups, dependent: :destroy
  has_many :screenshot_projects, dependent: :destroy
  has_many :screenshot_uploads, dependent: :destroy
  has_many :store_listings, dependent: :destroy
  has_many :release_notes, dependent: :destroy
  has_many :release_checklists, dependent: :destroy
  has_many :app_releases, dependent: :destroy
  has_many :keyword_rankings, dependent: :destroy
  has_many :app_reviews, dependent: :destroy
  has_many :rating_snapshots, dependent: :destroy
  has_many :review_response_templates, dependent: :destroy
  has_many :custom_product_pages, dependent: :destroy
  has_many :custom_product_page_versions, dependent: :destroy
  has_many :custom_product_page_localizations, dependent: :destroy
  # Audit events intentionally survive org deletion. The DB foreign key has
  # ON DELETE NULLIFY, so destroying an org sets organization_id = NULL on
  # its audit events rather than cascading them away. That keeps the
  # compliance trail (including the `organization_deleted` event itself,
  # which the controller writes just before destroy) readable by future
  # auditors even though it's no longer reachable via the normal
  # `organization.audit_events` scope.
  has_many :audit_events
  has_many :app_analytics_snapshots, dependent: :destroy
  has_many :org_sync_runs, dependent: :delete_all
  has_one :sso_configuration, dependent: :destroy
  # In-app notifications carry an `organization_id` FK and are scoped to
  # this org's events (sync results, credential expiries, etc). Once the
  # org is gone they have no meaningful UI context, so delete-all
  # (single SQL DELETE, no per-row callbacks) on org destroy. Without
  # this, `User#destroy!` on an owner whose org has notifications
  # belonging to teammates raises ActiveRecord::InvalidForeignKey on
  # the FK `notifications.organization_id -> organizations`, which
  # would otherwise silently strand soft-deleted owners past the 90-day
  # window in the purge job.
  has_many :notifications, dependent: :delete_all

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9][a-z0-9\-]*\z/, message: "must be lowercase letters, digits, and hyphens only" }
  validate :owner_organization_limit, on: :create
  # brand_settings values feed into CSS (colors) and a JS font-family
  # assignment (screenshot_editor_controller.js). Strong params accept any
  # string — enforce shape here so a direct POST can't inject arbitrary
  # CSS / font-family payloads that later reach the DOM.
  BRAND_COLOR_REGEX = /\A#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})\z/
  validate :brand_settings_well_formed

  # BYOK CMK ARN — must be a full KMS key ARN in us-east-1 with a lowercase
  # UUID key ID. Aliases and bare key IDs are rejected: aliases resolve at
  # call time and could be repointed; bare key IDs lose ownership context
  # in audit logs (mysigner-21). Nil/blank means "not configured" — fall
  # back to the env-default CMK.
  BYOK_KMS_KEY_ARN_REGEX =
    %r{\Aarn:aws:kms:us-east-1:\d{12}:key/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z}
  validates :byok_kms_key_arn,
            format: {
              with: BYOK_KMS_KEY_ARN_REGEX,
              message: "must be a full KMS key ARN in us-east-1 (alias and bare key IDs are not accepted)"
            },
            allow_blank: true

  # BYOK re-wrap (mysigner-21): whenever the customer registers a new CMK
  # ARN, switches to a different one, or clears it, re-wrap every existing
  # credential envelope under the new effective CMK. Runs INSIDE the org
  # save transaction so `update_column` writes from OrgRewrap roll back
  # atomically with the org row if KMS fails. Atomicity scope: DB rollback
  # yes; external KMS calls already billed to the customer's CloudTrail
  # are NOT rolled back.
  before_save :rewrap_credentials_on_byok_change, if: :byok_kms_key_arn_changed?

  # Exposes the most-recent OrgRewrap result so the controller can surface
  # per-class counts in the byok_registered/byok_cleared audit metadata after
  # the save commits. nil until the callback has fired in this object's
  # lifetime; controller defaults to {} via `|| {}` for the (rare) resave
  # path where the column didn't actually change.
  attr_reader :last_rewrap_counts

  before_validation :generate_slug, on: :create

  enum :access_state, {
    active: "active",
    plan_blocked: "plan_blocked"
  }, prefix: true

  scope :accessible, -> { access_state_supported? ? where(access_state: "active") : all }
  scope :plan_blocked, -> { access_state_supported? ? where(access_state: "plan_blocked") : none }

  def brand_configured?
    brand_settings.present? && brand_settings.values.any?(&:present?)
  end

  # True when this org has SAML SSO enforced -- members of this org MUST
  # sign in via SSO (the owner can still break-glass with password).
  def sso_enforced?
    return false unless entitlements.sso_enabled?
    sso_configuration&.enabled? && sso_configuration&.enforced?
  end

  # True when the org has at least one active ASC or Google Play credential.
  # Used to decide whether to show the unified "Sync" button anywhere.
  def any_active_platform_credential?
    app_store_connect_credentials.active.exists? ||
      google_play_credentials.active.exists?
  end

  scope :search, ->(term) {
    return all if term.blank?
    query = "%#{term.strip.downcase}%"
    left_joins(:owner)
      .where("LOWER(organizations.name) LIKE :q OR LOWER(users.email) LIKE :q", q: query)
  }

  after_create :ensure_owner_membership!
  before_destroy :clear_last_organization_reference

  scope :with_active_app_store_connect_credentials, -> { joins(:app_store_connect_credentials).where(app_store_connect_credentials: { active: true }).distinct }
  scope :with_active_google_play_credentials, -> { joins(:google_play_credentials).where(google_play_credentials: { active: true }).distinct }

  # Memoized per-instance, keyed by the owner's current plan_tier. The cache
  # transparently refreshes when the owner's plan changes (via either a normal
  # `update!` or a callback-bypass path like `update_columns`) so callers never
  # see stale entitlements without having to remember to `reload`.
  def entitlements
    current_tier = owner&.plan_tier.presence || "free"
    if @entitlements.nil? || @entitlements_owner_tier != current_tier
      @entitlements = Pricing::Entitlements.for_organization(self)
      @entitlements_owner_tier = current_tier
    end
    @entitlements
  end

  def reset_entitlements_memo!
    @entitlements = nil
    @entitlements_owner_tier = nil
  end

  def reload(*args)
    @entitlements = nil
    @entitlements_owner_tier = nil
    super
  end

  def accessible?
    return true unless self.class.access_state_supported?

    access_state_active?
  end

  def blocked_by_plan?
    return false unless self.class.access_state_supported?

    access_state_plan_blocked?
  end

  def access_state_badge_text
    return "Active" unless self.class.access_state_supported?
    return "Blocked by plan" if blocked_by_plan?

    access_state.to_s.titleize
  end

  def plan_tier
    owner&.plan_tier || "free"
  end

  def seat_usage_count
    memberships.count + organization_invitations.active.count
  end

  def seat_limit
    entitlements.max_seats_per_organization
  end

  def store_upload_enabled?
    entitlements.store_upload_enabled?
  end

  # The release-note review workflow only makes sense when there are at least
  # two members in the organization. For a solo user, submitting work to yourself
  # for review and then approving your own work is pointless ceremony.
  def supports_review_workflow?
    memberships_count.to_i > 1
  end

  def scheduled_sync_enabled?
    entitlements.scheduled_sync_enabled?
  end

  # Per-tier fan-out jitter. The cron tick enqueues N orgs in one transaction;
  # without jitter every job starts at the same instant and bursts N concurrent
  # provider-API calls (Apple/Google rate-limit per IP). Each job's start gets
  # a random delay within the tier's window, so workers see a smooth trickle
  # instead of a spike. Window is small relative to the tier's cadence.
  TIER_FAN_OUT_JITTER = {
    "team" => 5.minutes,
    "pro" => 15.minutes,
    "free" => 60.minutes
  }.freeze

  def self.enqueue_scheduled_sync_for(provider, tier: nil)
    provider_name = provider.to_s
    relation, job_class =
      case provider_name
      when "app_store_connect"
        [ with_active_app_store_connect_credentials, AppStoreConnectSyncJob ]
      when "google_play"
        [ with_active_google_play_credentials, GooglePlaySyncJob ]
      else
        raise ArgumentError, "Unsupported provider: #{provider}"
      end

    scope_with_optional_tier(relation, tier).find_each do |organization|
      perform_later_with_tier_jitter(job_class, tier, organization.id)
    end
  end

  def self.enqueue_review_syncs(tier: nil)
    enqueue_tiered_sync(ReviewSyncJob, tier: tier)
  end

  def self.enqueue_analytics_syncs(tier: nil)
    enqueue_tiered_sync(AnalyticsSyncJob, tier: tier)
  end

  def self.enqueue_tiered_sync(job_class, tier:)
    scope_with_optional_tier(all, tier).find_each do |org|
      perform_later_with_tier_jitter(job_class, tier, organization_id: org.id)
    end
  end

  # Filters a relation to orgs whose owner has the given tier. Always joins on
  # owner so orphaned orgs (a user destroyed without cascade) are excluded
  # symmetrically across both the tiered and untiered paths.
  def self.scope_with_optional_tier(relation, tier)
    scope = relation.joins(:owner)
    return scope unless tier

    tier_int = User.plan_tiers.fetch(tier.to_s)
    scope.where(users: { plan_tier: tier_int })
  end

  # Enqueues `job_class.perform_later(*args, **kwargs)` with optional tier
  # jitter. No tier (admin/manual fan-out) → no delay; tiered cron → random
  # delay drawn from TIER_FAN_OUT_JITTER. Each iteration calls `set` afresh so
  # every org gets an independent random offset.
  def self.perform_later_with_tier_jitter(job_class, tier, *args, **kwargs)
    jitter = tier ? TIER_FAN_OUT_JITTER[tier.to_s] : nil
    if jitter
      job_class.set(wait: rand(jitter.to_i).seconds).perform_later(*args, **kwargs)
    else
      job_class.perform_later(*args, **kwargs)
    end
  end

  private

  def self.access_state_supported?
    return false unless connection.data_source_exists?(table_name)
    return true if columns_hash.key?("access_state")

    reset_column_information
    columns_hash.key?("access_state")
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
    false
  end

  # Generates a URL-safe slug from the org name. Appends a numeric suffix if
  # the base slug collides. Used in SSO URLs (/users/auth/saml/:slug) and the
  # SP metadata endpoint. Idempotent -- if a slug is already set, leaves it.
  #
  # Note: this uses a TOCTOU check (`exists?` then `save`). Two concurrent
  # creates with the same name in different transactions can both observe
  # "slug is free" and then race to INSERT. The unique index rejects one of
  # them with ActiveRecord::RecordNotUnique; `save_with_slug_retry!` wraps
  # save calls to retry with a fresh candidate when that happens.
  # Bounded slug generation: try the base candidate, then a small fixed number
  # of numeric suffixes (base-1, base-2, ...). If we still collide, fall back to
  # a short random suffix instead of walking the sequence indefinitely.
  # Without the bound, an org name shared by hundreds of accounts (or a
  # malicious actor reserving a sequence) would force this method to scan every
  # row for each create. The unique index + save_with_slug_retry catches any
  # remaining collisions on the random fallback.
  SLUG_NUMERIC_SUFFIX_ATTEMPTS = 5

  def generate_slug
    return if slug.present?

    base = slug_base_from_name
    unless self.class.where.not(id: id).exists?(slug: base)
      self.slug = base
      return
    end

    SLUG_NUMERIC_SUFFIX_ATTEMPTS.times do |i|
      suffixed = "#{base}-#{i + 1}"
      unless self.class.where.not(id: id).exists?(slug: suffixed)
        self.slug = suffixed
        return
      end
    end

    # Pathological case: many orgs share this base name. Stop walking the
    # sequence and pick a short random suffix. 6 hex chars = 16M possibilities,
    # and save_with_slug_retry handles the remaining race window.
    self.slug = "#{base}-#{SecureRandom.hex(3)}"
  end

  def slug_base_from_name
    base = name.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    base.presence || "org"
  end

  # BYOK re-wrap callback (mysigner-21 sub-ticket 2.3). Fires when the
  # byok_kms_key_arn column actually changes (see `if: :byok_kms_key_arn_changed?`
  # on the callback registration). Re-wraps every credential envelope under
  # the new effective CMK — the customer's CMK on register/migrate, the env
  # default on clear.
  #
  # `byok_kms_key_arn.presence` collapses "" to nil so the "clear" path
  # passes nil into OrgRewrap (which then falls through to the env default
  # inside CredentialVault.encrypt).
  #
  # On any Aws::KMS::Errors::ServiceError we add a model error and
  # `throw :abort`. AR catches the abort, halts the save, and rolls back the
  # surrounding transaction — including any `update_column` writes
  # OrgRewrap issued on credential rows before the failure. The customer
  # sees a flash error in the controller; their CMK column stays at the
  # previous value (which already worked).
  def rewrap_credentials_on_byok_change
    new_arn = byok_kms_key_arn.presence
    @last_rewrap_counts = CredentialVault::OrgRewrap.run(organization: self, key_arn: new_arn)
  rescue Aws::KMS::Errors::ServiceError => e
    errors.add(:byok_kms_key_arn, "could not be applied: #{e.message}")
    throw :abort
  end

  public

  # Saves the organization, retrying on slug collisions caused by concurrent
  # creates (two users simultaneously creating an org with the same name both
  # land on the same candidate slug; the DB unique index rejects one of them
  # with RecordNotUnique). On collision, re-seed the slug with a short random
  # suffix and retry. Bounded at 3 attempts to avoid spinning on other
  # uniqueness violations (e.g. future indexes on other columns).
  def save_with_slug_retry
    attempts = 0
    begin
      save
    rescue ActiveRecord::RecordNotUnique => e
      raise unless e.message.to_s.include?("index_organizations_on_slug")
      attempts += 1
      raise if attempts >= 3

      regenerate_random_slug!
      retry
    end
  end

  private

  # Small randomized suffix used when we lose a slug race. Keeps suffix length
  # predictable (6 chars of hex = 16M combinations) so total slug stays short.
  def regenerate_random_slug!
    self.slug = "#{slug_base_from_name}-#{SecureRandom.hex(3)}"
  end

  def owner_organization_limit
    return unless owner

    limit = owner.entitlements.max_owned_organizations
    if owner.owned_organizations.where.not(id: id).count >= limit
      errors.add(
        :base,
        :quota_exhausted,
        message: "You can create a maximum of #{limit} organizations on the #{owner.plan_tier.titleize} plan",
        feature: :owned_organizations,
        current_plan: owner.plan_tier,
        next_plan: owner.entitlements.next_plan_tier
      )
    end
  end

  def ensure_owner_membership!
    memberships.where(user_id: owner_id).first_or_create!(role: :admin)
  end

  def clear_last_organization_reference
    User.where(last_organization_id: id).update_all(last_organization_id: nil)
  end

  # Blank values are allowed (fall back to defaults at render time). Any
  # non-blank value must be a valid hex color (for *_color fields) or an
  # entry in ScreenshotProject::GOOGLE_FONTS (for *_font fields). Unknown
  # keys inside brand_settings are stripped silently because Rails strong
  # params already filter to the explicit allowlist.
  def brand_settings_well_formed
    return unless brand_settings.is_a?(Hash)

    %w[primary_color secondary_color background_color text_color].each do |key|
      value = brand_settings[key]
      next if value.blank?
      unless value.is_a?(String) && value.match?(BRAND_COLOR_REGEX)
        errors.add(:brand_settings, "#{key} must be a valid hex color (e.g. #ff00aa)")
      end
    end

    %w[heading_font body_font].each do |key|
      value = brand_settings[key]
      next if value.blank?
      unless value.is_a?(String) && ScreenshotProject::GOOGLE_FONTS.include?(value)
        errors.add(:brand_settings, "#{key} is not an allowed font")
      end
    end
  end
end
