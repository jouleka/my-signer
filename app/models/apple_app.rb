class AppleApp < ApplicationRecord
  # CLI release defaults stored in the `cli_defaults` JSONB column.
  # These are the values that `mysigner ship appstore` reads for unattended
  # CI/CD submissions. The web UI has its own submission form on the Releases
  # tab and does NOT read these (see Releases > Submission tab).
  CLI_DEFAULT_KEYS = %w[
    release_type
    earliest_release_date
    auto_submit
    phased_release
    version_string
    build_number
    localizations
  ].freeze

  CLI_DEFAULT_RELEASE_TYPES = %w[AFTER_APPROVAL MANUAL SCHEDULED].freeze

  # Content fields that used to live on AppStoreRelease but are now canonical
  # on the primary-locale StoreListing. The API response merges these in for
  # CLI compatibility.
  CLI_DEFAULT_CONTENT_KEYS = %w[
    whats_new
    promotional_text
    support_url
    marketing_url
    privacy_policy_url
  ].freeze

  belongs_to :organization
  has_many :apple_builds, dependent: :destroy
  has_many :app_store_versions, dependent: :destroy
  has_many :testflight_beta_groups, dependent: :destroy
  has_many :store_listings, as: :listable, dependent: :destroy
  has_many :app_reviews, as: :reviewable, dependent: :destroy
  has_many :rating_snapshots, as: :snapshotable, dependent: :destroy
  has_many :app_analytics_snapshots, as: :snapshotable, dependent: :destroy
  has_many :custom_product_pages, dependent: :destroy
  has_many :tracked_keywords, dependent: :destroy
  has_many :apple_ads_recommendations, dependent: :destroy
  has_many :saved_keyword_ideas, dependent: :destroy

  # Find matching bundle ID record by identifier string
  def apple_bundle_id_record
    organization.apple_bundle_ids.find_by(identifier: bundle_id)
  end

  # The primary locale of this app on the App Store, as reported by Apple.
  # Apple stores `primaryLocale` on the App resource itself (not on a localization).
  # We sync the full attributes blob into raw_json, so this is a pure read.
  # Falls back to "en-US" only if Apple has not provided a value.
  def primary_locale
    attrs = raw_json.is_a?(Hash) ? (raw_json["attributes"] || {}) : {}
    attrs["primaryLocale"].presence || "en-US"
  end

  before_validation :squish_fields

  validates :app_store_id, presence: true, uniqueness: true
  validates :bundle_id, presence: true
  validates :sku, uniqueness: { scope: :organization_id }, allow_nil: true

  scope :by_bundle_id, ->(bundle_id) { where(bundle_id: bundle_id) }
  scope :with_cli_defaults, -> { where("cli_defaults <> '{}'::jsonb") }

  # ──────────────────────── CLI Defaults accessors ─────────────────────────

  # Typed accessors backed by the `cli_defaults` JSONB column.
  # Keep these in sync with CLI_DEFAULT_KEYS.
  def cli_release_type = (cli_defaults["release_type"].presence || "AFTER_APPROVAL")
  def cli_earliest_release_date
    raw = cli_defaults["earliest_release_date"]
    return nil if raw.blank?
    Time.zone.parse(raw)
  rescue ArgumentError, TypeError
    nil
  end
  def cli_auto_submit?   = (cli_defaults["auto_submit"] == true)
  def cli_phased_release? = (cli_defaults["phased_release"] == true)
  def cli_version_string = cli_defaults["version_string"].presence
  def cli_build_number   = cli_defaults["build_number"].presence
  def cli_localizations  = (cli_defaults["localizations"].is_a?(Array) ? cli_defaults["localizations"] : [])

  # True if any CLI default has been configured (i.e. the user has visited
  # the CLI Defaults page and saved settings).
  def cli_defaults_configured?
    cli_defaults.is_a?(Hash) && cli_defaults.any?
  end

  # Updates the cli_defaults JSONB column from a params-like hash. Only
  # whitelisted keys are written. Returns true on success, false on
  # validation failure (exposed via #cli_defaults_errors).
  #
  # Accepts string or symbol keys.
  def update_cli_defaults(params)
    @cli_defaults_errors = {}
    normalized = normalize_cli_default_params(params)
    validate_cli_defaults!(normalized)
    return false if @cli_defaults_errors.any?

    self.cli_defaults = cli_defaults.merge(normalized.stringify_keys).reject { |_k, v| v.nil? || v == "" }
    save
  end

  def cli_defaults_errors
    @cli_defaults_errors ||= {}
  end

  # Builds the JSON payload returned by Api::V1::AppStoreReleasesController
  # and also used by legacy consumers. Merges cli_defaults with the primary
  # StoreListing's content fields for backward compatibility with the CLI.
  #
  # The record `id` in this payload is the AppleApp's ID, not a separate
  # AppStoreRelease record — the CLI uses it as the URL segment for PATCH.
  def cli_defaults_api_payload
    content = primary_store_listing_content
    {
      id: id,
      apple_bundle_id_id: apple_bundle_id_record&.id,
      bundle_identifier: bundle_id,
      app_name: name.presence || bundle_id,
      whats_new: content[:whats_new],
      promotional_text: content[:promotional_text],
      support_url: content[:support_url],
      marketing_url: content[:marketing_url],
      privacy_policy_url: content[:privacy_policy_url],
      auto_submit: cli_auto_submit?,
      phased_release: cli_phased_release?,
      version_string: cli_version_string,
      build_number: cli_build_number,
      localizations: cli_localizations,
      release_type: cli_release_type,
      earliest_release_date: cli_earliest_release_date&.iso8601,
      created_at: created_at.iso8601,
      updated_at: updated_at.iso8601
    }
  end

  # Copies content fields (whats_new / support_url / etc.) from an incoming
  # params hash to the primary-locale StoreListing, mirroring the legacy
  # sync_content_to_store_listing helper in the API controller. Only writes
  # fields present in the params (sparse update).
  def sync_content_fields_to_store_listing(params)
    return unless params
    content_values = params.to_h.with_indifferent_access.slice(*CLI_DEFAULT_CONTENT_KEYS).compact_blank
    return if content_values.empty?

    listing = store_listings.find_or_initialize_by(locale: primary_locale)
    listing.organization ||= organization if listing.new_record?
    listing.sync_status ||= "draft"
    listing.assign_attributes(content_values)
    listing.save
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("AppleApp#sync_content_fields_to_store_listing failed: #{e.message}")
    false
  end

  private

  def squish_fields
    self.name = name.to_s.strip
    self.bundle_id = bundle_id.to_s.strip
    self.sku = sku.to_s.strip
    self.app_store_id = app_store_id.to_s.strip
  end

  # Normalizes CLI default params to typed values. Strings with whitespace
  # are stripped; release_type is uppercased; booleans are cast; dates are
  # parsed to ISO 8601 UTC strings.
  def normalize_cli_default_params(params)
    hash = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
    hash = hash.with_indifferent_access.slice(*CLI_DEFAULT_KEYS)

    if hash.key?(:release_type)
      value = hash[:release_type].to_s.strip
      hash[:release_type] = value.presence && value.upcase
    end

    if hash.key?(:version_string)
      hash[:version_string] = hash[:version_string].to_s.strip.presence
    end

    if hash.key?(:build_number)
      raw = hash[:build_number].to_s.strip
      hash[:build_number] = raw.presence
    end

    if hash.key?(:auto_submit)
      hash[:auto_submit] = ActiveModel::Type::Boolean.new.cast(hash[:auto_submit])
    end

    if hash.key?(:phased_release)
      hash[:phased_release] = ActiveModel::Type::Boolean.new.cast(hash[:phased_release])
    end

    if hash.key?(:earliest_release_date)
      raw = hash[:earliest_release_date]
      if raw.is_a?(String) && raw.present?
        parsed = (Time.zone.parse(raw) rescue nil)
        hash[:earliest_release_date] = parsed&.utc&.iso8601
      elsif raw.respond_to?(:iso8601)
        hash[:earliest_release_date] = raw.utc.iso8601
      else
        hash[:earliest_release_date] = nil
      end
    end

    if hash.key?(:localizations) && !hash[:localizations].is_a?(Array)
      hash[:localizations] = []
    end

    hash
  end

  def validate_cli_defaults!(hash)
    if hash.key?(:release_type) && hash[:release_type].present?
      unless CLI_DEFAULT_RELEASE_TYPES.include?(hash[:release_type])
        @cli_defaults_errors[:release_type] = "must be one of #{CLI_DEFAULT_RELEASE_TYPES.join(', ')}"
      end
    end

    if hash.key?(:build_number) && hash[:build_number].present?
      unless hash[:build_number].to_s.match?(/\A[1-9]\d*\z/)
        @cli_defaults_errors[:build_number] = "is not a number"
      end
    end

    # release_type is SCHEDULED → earliest_release_date required AND ≥1h future.
    effective_release_type = hash.fetch(:release_type, cli_release_type)
    if effective_release_type == "SCHEDULED"
      raw_date = hash.fetch(:earliest_release_date, cli_defaults["earliest_release_date"])
      if raw_date.blank?
        @cli_defaults_errors[:earliest_release_date] = "can't be blank for SCHEDULED release"
      else
        parsed = raw_date.is_a?(String) ? (Time.zone.parse(raw_date) rescue nil) : raw_date
        if parsed && parsed < 1.hour.from_now
          @cli_defaults_errors[:earliest_release_date] = "must be at least 1 hour in the future"
        end
      end
    end
  end

  def primary_store_listing_content
    listing = store_listings.find_by(locale: primary_locale) || store_listings.first
    CLI_DEFAULT_CONTENT_KEYS.each_with_object({}) do |field, hash|
      hash[field.to_sym] = listing&.send(field).presence
    end
  end
end
