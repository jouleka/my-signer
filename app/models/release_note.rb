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
  before_validation :auto_render_text, if: -> { template_data_changed? && (rendered_text.blank? || !rendered_text_changed?) }
  before_save :invalidate_content_state, if: -> { persisted? && content_changed? }
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
  validate :translations_structure
  validate :reviewed_content_is_frozen
  validates :review_decision, inclusion: { in: %w[approved rejected] }, allow_nil: true

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
    with_lock do
      raise "Cannot apply while this release note needs approval." if review_required?
      raise "Cannot apply a #{status} release note." unless content_editable?
      raise "Write release notes before applying them." if rendered_text.blank?
      raise "Wait for the AI operation to finish before applying." if ai_pending?
      # Apply rendered_text to base locale StoreListing
      base_listing = organization.store_listings
        .where(listable: listable, locale: locale)
        .first

      raise "Create a store listing for #{locale} before applying." unless base_listing
      base_listing.update!(whats_new: rendered_text)

      # Apply translations to other locale StoreListings
      translations.each do |target_locale, translated_text|
        listing = organization.store_listings
          .where(listable: listable, locale: target_locale)
          .first
        raise "Create a store listing for #{target_locale} before applying." unless listing
        listing.update!(whats_new: translated_text)
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
    with_lock do
      raise "Cannot submit: already #{status}" unless status == "draft"
      raise "Write release notes before submitting for review." if rendered_text.blank?
      raise "Wait for the AI operation to finish before submitting for review." if ai_pending?
      update!(status: "pending_review", submitted_for_review_at: Time.current,
        review_decision: nil, reviewed_by: nil, reviewed_at: nil, review_comment: nil)
    end
  end

  def approve_review!(user:, comment: nil)
    with_lock do
      raise "Cannot approve: status is #{status}, not pending_review" unless status == "pending_review"
      update!(status: "draft", review_decision: "approved", reviewed_by: user,
        reviewed_at: Time.current, review_comment: comment.to_s.strip.presence)
    end
  end

  def reject_review!(user:, comment:)
    with_lock do
      raise "Cannot reject: status is #{status}, not pending_review" unless status == "pending_review"
      raise "Rejection requires a comment" if comment.to_s.strip.blank?
      update!(status: "draft", review_decision: "rejected", reviewed_by: user,
        reviewed_at: Time.current, review_comment: comment.to_s.strip)
    end
  end

  def pending_review?
    status == "pending_review"
  end

  def reviewed?
    reviewed_at.present?
  end

  def approved?
    reviewed? && review_decision == "approved"
  end

  def rejected?
    reviewed? && review_decision == "rejected" && status == "draft"
  end

  # The review workflow only applies while the organization has more than one
  # member. A solo org (e.g. after teammates leave) must not be deadlocked by a
  # note left in pending_review or rejected, since nobody can approve it.
  def review_workflow_active?
    organization&.supports_review_workflow? || false
  end

  def review_required?
    return false unless review_workflow_active?
    pending_review? || (submitted_for_review_at.present? && !approved?)
  end

  # Without an active review workflow a pending_review note behaves as a draft.
  def content_editable?
    %w[draft applied].include?(status) || (pending_review? && !review_workflow_active?)
  end

  def ai_pending?
    operation = metadata.fetch("ai_operation", {})
    %w[pending running].include?(operation["status"]) && operation["started_at"].to_s > 1.hour.ago.iso8601
  end

  def content_snapshot
    attributes.slice("version_string", "locale", "template_data", "rendered_text", "translations", "status")
  end

  private

  def normalize_locale
    return if locale.blank?
    self.locale = locale.to_s.strip
  end

  def auto_render_text
    return unless template_data.is_a?(Hash) && template_data.values.all? { |items| items.is_a?(Array) && items.all? { |item| item.is_a?(String) } }
    self.rendered_text = render_text_from_template
  end

  def content_changed?
    %w[version_string locale template_data rendered_text translations].any? { |field| will_save_change_to_attribute?(field) }
  end

  def invalidate_content_state
    if approved?
      self.review_decision = nil
      self.reviewed_by = nil
      self.reviewed_at = nil
      self.review_comment = nil
    end
    if status == "applied"
      self.status = "draft"
      self.applied_at = nil
    end
  end

  def reviewed_content_is_frozen
    if persisted? && status_in_database == "pending_review" && content_changed? && review_workflow_active?
      errors.add(:base, "Release notes cannot be edited while awaiting review.")
    end
  end

  def translations_structure
    unless translations.is_a?(Hash)
      errors.add(:translations, "must be a hash")
      return
    end
    translations.each do |target_locale, text|
      unless target_locale.match?(LOCALE_FORMAT) && target_locale != locale && text.is_a?(String)
        errors.add(:translations, "must map other valid locales to text")
        next
      end
      errors.add(:translations, "for #{target_locale} is too long (maximum is #{char_limit} characters)") if text.length > char_limit
    end
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
