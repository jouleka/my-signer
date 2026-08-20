class ReleaseNote < ApplicationRecord
  belongs_to :organization
  belongs_to :listable, polymorphic: true
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  # Explicit live-refresh trigger for subscribed pages (turbo_stream_from @release_note).
  # Used by the AI rewrite / translation jobs after they finish saving. We do NOT
  # use `broadcasts_refreshes` because that fires on every update, which would
  # interrupt the autosave flow (the page would morph mid-keystroke).
  def trigger_live_refresh
    broadcast_refresh_later_to(self)
  end

  STATUSES = %w[draft pending_review applied published archived].freeze
  SOURCES = %w[manual ai_rewrite import].freeze
  TEMPLATE_CATEGORIES = %w[new improved fixed].freeze

  CATEGORY_HEADINGS = {
    "new" => "NEW",
    "improved" => "IMPROVED",
    "fixed" => "FIXED"
  }.freeze

  CHAR_LIMITS = {
    "AppleApp" => 4000,
    "AndroidApp" => 500
  }.freeze

  # BCP 47 locale code: 2-3 letter language code, optionally followed by up to
  # three subtag segments (region, script, variant). Examples: en, en-US, fr-CA,
  # zh-Hans, zh-Hans-CN, es-419.
  LOCALE_FORMAT = /\A[a-zA-Z]{2,3}(-[a-zA-Z0-9]{2,8}){0,3}\z/

  # Loose semantic version: 1, 1.2, 1.2.3, 1.2.3.4 with optional pre-release.
  VERSION_STRING_FORMAT = /\A[0-9]+(\.[0-9]+){0,3}([\-+][0-9A-Za-z.\-]+)?\z/

  # Build numbers can be plain integers (Apple/Google) or dotted (some workflows).
  BUILD_NUMBER_FORMAT = /\A[0-9A-Za-z.\-]+\z/

  before_validation :normalize_locale
  before_save :auto_render_text, if: -> { template_data_changed? && rendered_text.blank? }
  before_save :set_applied_timestamp, if: -> { status_changed? && status == "applied" }
  before_save :set_published_timestamp, if: -> { status_changed? && status == "published" }

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }, allow_nil: true
  validates :locale, presence: true,
    format: { with: LOCALE_FORMAT, message: "must be a valid BCP 47 locale code (e.g., en-US, de, fr-CA, zh-Hans)" }
  validates :version_string,
    format: { with: VERSION_STRING_FORMAT, message: "must look like a version (e.g., 1, 1.2, 2.1.0, 2.1.0-beta)" },
    allow_blank: true
  validates :build_number,
    format: { with: BUILD_NUMBER_FORMAT, message: "must contain only letters, digits, dots, or dashes" },
    allow_blank: true
  validate :rendered_text_within_char_limit
  validate :template_data_structure

  scope :for_app, ->(listable) { where(listable: listable) }
  scope :drafts, -> { where(status: "draft") }
  scope :pending_review, -> { where(status: "pending_review") }
  scope :applied, -> { where(status: "applied") }
  scope :published, -> { where(status: "published") }
  scope :archived, -> { where(status: "archived") }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_version, -> { order(Arel.sql("version_string DESC NULLS LAST, created_at DESC")) }

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

  def char_limit
    CHAR_LIMITS[listable_type] || 4000
  end

  def render_text_from_template
    parts = []
    TEMPLATE_CATEGORIES.each do |category|
      items = template_data[category] || template_data[category.to_sym]
      next if items.blank?
      items = items.select(&:present?)
      next if items.empty?

      heading = CATEGORY_HEADINGS[category]
      parts << heading
      items.each { |item| parts << "- #{item}" }
      parts << ""
    end
    parts.join("\n").strip
  end

  def apply_to_store_listings!
    transaction do
      # Apply rendered_text to base locale StoreListing
      base_listing = organization.store_listings
        .where(listable: listable, locale: locale)
        .first

      if base_listing
        base_listing.update!(whats_new: rendered_text)
      end

      # Apply translations to other locale StoreListings
      translations.each do |target_locale, translated_text|
        listing = organization.store_listings
          .where(listable: listable, locale: target_locale)
          .first
        listing&.update!(whats_new: translated_text)
      end

      update!(status: "applied", applied_at: Time.current)
    end
  end

  # Parses a stored translation (a flat string) into an array of
  # `{heading:, items:[...]}` sections. Sections are separated by blank lines.
  # Within a section the first non-blank line is the heading, remaining lines
  # (prefixed with -, •, or *) are the items. Matches the format produced by
  # ReleaseNoteTranslationJob. Returns [] when the translation is blank or
  # unparseable — callers should handle that with empty slots.
  def parse_translation_sections(locale)
    text = (translations || {})[locale.to_s].to_s
    return [] if text.strip.empty?

    blocks = text.split(/(?:\r?\n){2,}/)
    sections = []
    blocks.each do |block|
      lines = block.split(/\r?\n/).map(&:strip).reject(&:empty?)
      next if lines.empty?
      first = lines.first
      if first.start_with?("-", "•", "*")
        heading = ""
        items = lines.map { |l| l.sub(/\A[\-•*]\s*/, "") }.reject(&:empty?)
      else
        heading = first
        items = lines.drop(1).map { |l| l.sub(/\A[\-•*]\s*/, "") }.reject(&:empty?)
      end
      sections << { heading: heading, items: items }
    end
    sections
  end

  def diff_with(other_note)
    return nil unless other_note

    {
      version_string: { before: other_note.version_string, after: version_string },
      rendered_text: { before: other_note.rendered_text, after: rendered_text },
      template_data: { before: other_note.template_data, after: template_data }
    }
  end

  def submit_for_review!(user:)
    raise "Cannot submit: already #{status}" unless status == "draft"
    update!(
      status: "pending_review",
      submitted_for_review_at: Time.current
    )
  end

  def approve_review!(user:, comment: nil)
    raise "Cannot approve: status is #{status}, not pending_review" unless status == "pending_review"
    update!(
      status: "draft", # back to draft so it can be applied
      reviewed_by: user,
      reviewed_at: Time.current,
      review_comment: comment.presence
    )
  end

  def reject_review!(user:, comment:)
    raise "Cannot reject: status is #{status}, not pending_review" unless status == "pending_review"
    raise "Rejection requires a comment" if comment.to_s.strip.blank?
    update!(
      status: "draft",
      reviewed_by: user,
      reviewed_at: Time.current,
      review_comment: comment
    )
  end

  def pending_review?
    status == "pending_review"
  end

  def reviewed?
    reviewed_at.present?
  end

  def approved?
    reviewed? && review_comment.blank?
  end

  def rejected?
    reviewed? && review_comment.present? && status == "draft"
  end

  private

  def normalize_locale
    return if locale.blank?
    self.locale = locale.to_s.strip
  end

  def auto_render_text
    text = render_text_from_template
    self.rendered_text = text if text.present?
  end

  def set_applied_timestamp
    self.applied_at = Time.current
  end

  def set_published_timestamp
    self.published_at = Time.current
  end

  def rendered_text_within_char_limit
    return if rendered_text.blank?
    limit = char_limit
    if rendered_text.length > limit
      errors.add(:rendered_text, "is too long (maximum is #{limit} characters, got #{rendered_text.length})")
    end
  end

  def template_data_structure
    return if template_data.blank? || template_data == {}

    unless template_data.is_a?(Hash)
      errors.add(:template_data, "must be a hash")
      return
    end

    template_data.each do |key, value|
      unless TEMPLATE_CATEGORIES.include?(key.to_s)
        errors.add(:template_data, "contains invalid category: #{key}")
        return
      end

      unless value.is_a?(Array)
        errors.add(:template_data, "category '#{key}' must be an array")
        return
      end

      unless value.all? { |item| item.is_a?(String) }
        errors.add(:template_data, "category '#{key}' must contain only strings")
        return
      end
    end
  end
end
