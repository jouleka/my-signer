class AndroidApp < ApplicationRecord
  # CLI release defaults stored in the `cli_defaults` JSONB column.
  # These are the values that `mysigner ship android` reads for unattended
  # CI/CD releases. Mirrors AppleApp#cli_defaults but with Android-specific
  # knobs — Google Play has no equivalent of iOS's phased_release/release_type,
  # so we model staged rollouts instead (status + userFraction).
  CLI_DEFAULT_KEYS = %w[
    default_track
    default_status
    default_user_fraction
    default_in_app_update_priority
    changes_not_sent_for_review
    release_notes
    country_targeting
    release_name
  ].freeze

  VALID_TRACKS = %w[internal alpha beta production].freeze
  # Draft = uploaded but not yet sent to users. Closest analog to iOS MANUAL,
  # though Google Play's true "hold after review" requires Managed Publishing
  # (toggled in the Play Console, not the API — we document this limitation).
  VALID_STATUSES = %w[draft inProgress completed].freeze

  belongs_to :organization
  has_many :android_builds, dependent: :destroy
  has_many :android_tracks, dependent: :destroy
  has_many :play_store_releases, dependent: :destroy
  has_one :play_store_release,
          -> { order(Arel.sql("COALESCE(released_at, created_at) DESC")) },
          class_name: "PlayStoreRelease"
  has_many :android_keystores, dependent: :nullify
  has_many :store_listings, as: :listable, dependent: :destroy
  has_many :app_reviews, as: :reviewable, dependent: :destroy
  has_many :rating_snapshots, as: :snapshotable, dependent: :destroy
  has_many :app_analytics_snapshots, as: :snapshotable, dependent: :destroy

  before_validation :squish_fields

  validates :package_name, presence: true, length: { maximum: 200 }, format: { with: /\A[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)+\z/ }
  validates :package_name, uniqueness: { scope: :organization_id }

  scope :with_cli_defaults, -> { where("cli_defaults <> '{}'::jsonb") }

  # The primary locale of this app on Google Play, as reported by Google.
  # Google stores it as `default_language` on the app resource. Falls back to
  # "en-US" only if Google has not provided a value.
  # Normalizes underscore format (pt_BR) to hyphen format (pt-BR) to match
  # our canonical storage format used in StoreListing.locale.
  def primary_locale
    raw = default_language.to_s.strip
    return "en-US" if raw.blank?
    raw.tr("_", "-")
  end

  # ──────────────────────── CLI Defaults accessors ─────────────────────────

  def cli_default_track          = cli_defaults["default_track"].presence
  def cli_default_status         = (cli_defaults["default_status"].presence || "completed")
  def cli_default_user_fraction  = cli_defaults["default_user_fraction"]
  def cli_default_in_app_update_priority = cli_defaults["default_in_app_update_priority"]
  def cli_changes_not_sent_for_review? = (cli_defaults["changes_not_sent_for_review"] == true)
  def cli_release_name           = cli_defaults["release_name"].presence
  def cli_release_notes          = (cli_defaults["release_notes"].is_a?(Hash) ? cli_defaults["release_notes"] : {})
  def cli_country_targeting      = (cli_defaults["country_targeting"].is_a?(Hash) ? cli_defaults["country_targeting"] : nil)

  def cli_defaults_configured?
    cli_defaults.is_a?(Hash) && cli_defaults.any?
  end

  # Updates the cli_defaults JSONB column from a params-like hash. Only
  # whitelisted keys are written. Returns true on success, false on
  # validation failure (exposed via #cli_defaults_errors).
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

  # JSON payload returned to the CLI when it fetches defaults. The CLI reads
  # these at ship time and layers CLI flag overrides on top.
  def cli_defaults_api_payload
    {
      id: id,
      package_name: package_name,
      app_name: name.presence || package_name,
      default_track: cli_default_track,
      default_status: cli_default_status,
      default_user_fraction: cli_default_user_fraction,
      default_in_app_update_priority: cli_default_in_app_update_priority,
      changes_not_sent_for_review: cli_changes_not_sent_for_review?,
      release_name: cli_release_name,
      release_notes: cli_release_notes,
      country_targeting: cli_country_targeting,
      primary_locale: primary_locale,
      created_at: created_at.iso8601,
      updated_at: updated_at.iso8601
    }
  end

  private

  def squish_fields
    self.name = name.to_s.strip
    self.package_name = package_name.to_s.strip
    self.default_language = default_language.to_s.strip
  end

  # Normalizes CLI default params: strips strings, casts booleans, coerces
  # floats, whitelists keys. Unknown keys are silently dropped.
  def normalize_cli_default_params(params)
    hash = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
    hash = hash.with_indifferent_access.slice(*CLI_DEFAULT_KEYS)

    if hash.key?(:default_track)
      hash[:default_track] = hash[:default_track].to_s.strip.downcase.presence
    end

    if hash.key?(:default_status)
      hash[:default_status] = hash[:default_status].to_s.strip.presence
    end

    if hash.key?(:default_user_fraction)
      raw = hash[:default_user_fraction]
      hash[:default_user_fraction] = case raw
      when nil, "" then nil
      else raw.to_f
      end
    end

    if hash.key?(:default_in_app_update_priority)
      raw = hash[:default_in_app_update_priority]
      hash[:default_in_app_update_priority] = (raw.nil? || raw == "") ? nil : raw.to_i
    end

    if hash.key?(:changes_not_sent_for_review)
      hash[:changes_not_sent_for_review] = ActiveModel::Type::Boolean.new.cast(hash[:changes_not_sent_for_review])
    end

    if hash.key?(:release_name)
      hash[:release_name] = hash[:release_name].to_s.strip.presence
    end

    if hash.key?(:release_notes)
      raw = hash[:release_notes]
      # Accept Hash (locale => text) or reject anything else.
      hash[:release_notes] = raw.is_a?(Hash) ? raw.transform_keys(&:to_s).reject { |_, v| v.to_s.strip.empty? } : {}
      hash[:release_notes] = nil if hash[:release_notes].empty?
    end

    if hash.key?(:country_targeting)
      raw = hash[:country_targeting]
      if raw.is_a?(Hash)
        countries = Array(raw["countries"] || raw[:countries]).map(&:to_s).map(&:strip).reject(&:empty?)
        include_rest = ActiveModel::Type::Boolean.new.cast(raw["include_rest_of_world"] || raw[:include_rest_of_world])
        hash[:country_targeting] = countries.any? ? { "countries" => countries, "include_rest_of_world" => include_rest } : nil
      else
        hash[:country_targeting] = nil
      end
    end

    hash
  end

  def validate_cli_defaults!(hash)
    if hash.key?(:default_track) && hash[:default_track].present?
      unless VALID_TRACKS.include?(hash[:default_track])
        @cli_defaults_errors[:default_track] = "must be one of #{VALID_TRACKS.join(', ')}"
      end
    end

    if hash.key?(:default_status) && hash[:default_status].present?
      unless VALID_STATUSES.include?(hash[:default_status])
        @cli_defaults_errors[:default_status] = "must be one of #{VALID_STATUSES.join(', ')}"
      end
    end

    # Google Play rule: userFraction is strictly (0, 1) and only valid when
    # status=inProgress. Enforce both constraints client-side so the CLI
    # doesn't blow up on an Apple-like 400 later.
    effective_status = hash.fetch(:default_status, cli_default_status)
    fraction = hash.fetch(:default_user_fraction, cli_default_user_fraction)
    if fraction.present?
      unless fraction.is_a?(Numeric) && fraction > 0.0 && fraction < 1.0
        @cli_defaults_errors[:default_user_fraction] = "must be between 0 and 1 (exclusive)"
      end
      if effective_status != "inProgress" && @cli_defaults_errors[:default_user_fraction].blank?
        @cli_defaults_errors[:default_user_fraction] = "only valid when default_status is inProgress"
      end
    end

    if hash.key?(:default_in_app_update_priority) && hash[:default_in_app_update_priority].present?
      priority = hash[:default_in_app_update_priority]
      unless priority.is_a?(Integer) && priority >= 0 && priority <= 5
        @cli_defaults_errors[:default_in_app_update_priority] = "must be an integer between 0 and 5"
      end
    end

    if hash.key?(:release_notes) && hash[:release_notes].is_a?(Hash)
      # Google Play expects BCP-47 locale codes (en-US, de-DE, pt-BR, etc.).
      # Reject obviously invalid keys so the error surfaces at save time
      # rather than during the actual Play upload.
      bad_keys = hash[:release_notes].keys.reject { |k| k.to_s.match?(/\A[a-z]{2,3}(-[A-Za-z0-9]+)*\z/) }
      if bad_keys.any?
        @cli_defaults_errors[:release_notes] = "contains non-BCP-47 locale keys: #{bad_keys.join(', ')}"
      end
    end
  end
end
