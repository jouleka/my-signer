class StoreListing < ApplicationRecord
  belongs_to :organization
  belongs_to :listable, polymorphic: true

  # Explicit live-refresh trigger for subscribed pages (turbo_stream_from
  # @store_listing). Used by StoreListingTranslationJob after it writes
  # translated fields onto this record. Consistent with ReleaseNote.
  def trigger_live_refresh
    broadcast_refresh_later_to(self)
  end

  SYNC_STATUSES = %w[draft synced modified conflict partially_synced].freeze
  TRANSLATION_STATUSES = %w[pending needs_review approved].freeze

  # Character limits per platform
  # iOS limits are from App Store Connect; Android limits from Google Play Console
  CHAR_LIMITS = {
    "AppleApp" => {
      app_name: 30,
      subtitle: 30,
      keywords: 100,
      description: 4000,
      promotional_text: 170,
      whats_new: 4000
    },
    "AndroidApp" => {
      app_name: 30,
      short_description: 80,
      description: 4000,
      whats_new: 500
    }
  }.freeze

  # Fields that only apply to iOS
  IOS_ONLY_FIELDS = %i[subtitle keywords promotional_text].freeze
  # Fields that only apply to Android
  ANDROID_ONLY_FIELDS = %i[short_description].freeze

  before_validation :normalize_fields
  before_save :detect_modification

  validates :locale, presence: true,
    format: { with: /\A[a-zA-Z]{2,3}(-[a-zA-Z0-9]{2,8}){0,3}\z/, message: "must be a valid locale code (e.g., en-US)" },
    uniqueness: { scope: [ :listable_type, :listable_id ], message: "already exists for this app" }
  validates :sync_status, inclusion: { in: SYNC_STATUSES }
  validates :translation_status, inclusion: { in: TRANSLATION_STATUSES }, allow_nil: true

  # Platform-specific character limit validations
  validate :character_limits
  validate :platform_field_restrictions
  validate :url_format

  scope :for_apple, -> { where(listable_type: "AppleApp") }
  scope :for_android, -> { where(listable_type: "AndroidApp") }
  scope :for_locale, ->(locale) { where(locale: locale) }
  scope :synced, -> { where(sync_status: "synced") }
  scope :modified, -> { where(sync_status: "modified") }
  scope :drafts, -> { where(sync_status: "draft") }
  scope :needs_review, -> { where(translation_status: "needs_review") }

  def platform
    case listable_type
    when "AppleApp" then :ios
    when "AndroidApp" then :android
    end
  end

  def ios?
    listable_type == "AppleApp"
  end

  def android?
    listable_type == "AndroidApp"
  end

  def char_limit_for(field)
    CHAR_LIMITS.dig(listable_type, field.to_sym)
  end

  def char_usage_for(field)
    value = send(field)
    return 0 if value.blank?
    value.length
  end

  def mark_synced!
    update!(sync_status: "synced", last_synced_at: Time.current)
  end

  def mark_modified!
    update!(sync_status: "modified") if sync_status == "synced"
  end

  def mark_needs_review!
    update!(translation_status: "needs_review")
  end

  def approve_translation!
    update!(translation_status: "approved")
  end

  # Whether this listing's comma-separated keywords field contains the given
  # keyword after NFC normalization + downcase + whitespace collapse. Used by
  # the Suggestions tab to render "already in keywords" strike-through state.
  def includes_keyword?(keyword)
    return false if keywords.blank?
    needle = Aso::KeywordNormalizer.call(keyword)
    return false if needle.blank?

    keywords.to_s.split(",").any? do |raw|
      Aso::KeywordNormalizer.call(raw) == needle
    end
  end

  private

  def normalize_fields
    self.locale = locale.to_s.strip.presence
    self.app_name = app_name.to_s.strip.presence
    self.subtitle = subtitle.to_s.strip.presence
    self.keywords = keywords.to_s.strip.presence
    self.short_description = short_description.to_s.strip.presence
    self.support_url = support_url.to_s.strip.presence
    self.marketing_url = marketing_url.to_s.strip.presence
    self.privacy_policy_url = privacy_policy_url.to_s.strip.presence
    self.description = description.to_s.strip.presence
    self.promotional_text = promotional_text.to_s.strip.presence
    self.whats_new = whats_new.to_s.strip.presence
  end

  def detect_modification
    return unless persisted? && sync_status_was == "synced"
    # Don't auto-modify if sync_status is being explicitly changed (e.g., by importer)
    return if changes.key?("sync_status")

    content_fields = %w[app_name subtitle keywords short_description description
                        promotional_text whats_new support_url marketing_url privacy_policy_url]
    if content_fields.any? { |f| changes.key?(f) }
      self.sync_status = "modified"
    end
  end

  def character_limits
    limits = CHAR_LIMITS[listable_type]
    return unless limits

    limits.each do |field, limit|
      value = send(field)
      next if value.blank?
      if value.length > limit
        errors.add(field, "is too long (maximum is #{limit} characters, got #{value.length})")
      end
    end
  end

  def platform_field_restrictions
    if ios?
      ANDROID_ONLY_FIELDS.each do |field|
        if send(field).present?
          errors.add(field, "is not applicable for iOS apps")
        end
      end
    elsif android?
      IOS_ONLY_FIELDS.each do |field|
        if send(field).present?
          errors.add(field, "is not applicable for Android apps")
        end
      end
    end
  end

  def url_format
    %i[support_url marketing_url privacy_policy_url].each do |field|
      value = send(field)
      next if value.blank?
      uri = URI.parse(value)
      unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        errors.add(field, "must be a valid HTTP or HTTPS URL")
      end
    rescue URI::InvalidURIError
      errors.add(field, "is not a valid URL")
    end
  end
end
