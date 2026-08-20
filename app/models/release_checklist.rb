class ReleaseChecklist < ApplicationRecord
  belongs_to :organization
  belongs_to :listable, polymorphic: true, optional: true
  belongs_to :created_by, class_name: "User", optional: true

  PLATFORMS = %w[ios android both].freeze

  DEFAULT_ITEMS = [
    { "key" => "release_notes_written", "label" => "Release notes written?", "checked" => false, "required" => true, "category" => "content" },
    { "key" => "all_locales_translated", "label" => "All locales translated?", "checked" => false, "required" => true, "category" => "content" },
    { "key" => "screenshots_updated", "label" => "Screenshots updated?", "checked" => false, "required" => false, "category" => "assets" },
    { "key" => "description_reviewed", "label" => "App description reviewed?", "checked" => false, "required" => false, "category" => "content" },
    { "key" => "build_tested", "label" => "Build tested on device?", "checked" => false, "required" => true, "category" => "quality" },
    { "key" => "privacy_policy_current", "label" => "Privacy policy up to date?", "checked" => false, "required" => false, "category" => "compliance" }
  ].freeze

  before_save :compute_all_required_complete

  validates :platform, inclusion: { in: PLATFORMS }, allow_nil: true
  validate :items_structure

  scope :for_app, ->(listable) { where(listable: listable) }
  scope :templates, -> { where(listable_type: nil, listable_id: nil) }
  scope :for_version, ->(version) { where(version_string: version) }

  def check_item!(key, user = nil)
    item = find_item(key)
    return false unless item

    item["checked"] = true
    item["checked_by_id"] = user&.id
    item["checked_at"] = Time.current.iso8601
    save!
  end

  def uncheck_item!(key)
    item = find_item(key)
    return false unless item

    item["checked"] = false
    item["checked_by_id"] = nil
    item["checked_at"] = nil
    save!
  end

  # Add a custom item to the checklist
  # @param label [String]
  # @param required [Boolean]
  # @param user [User, nil]
  # @return [Boolean] true if saved
  def add_custom_item!(label:, required: false, user: nil)
    return false if label.to_s.strip.blank?

    self.custom_items ||= []

    # Prevent duplicates by label (case insensitive)
    return false if custom_items.any? { |i| i["label"].to_s.strip.downcase == label.to_s.strip.downcase }

    key = generate_custom_item_key(label)

    custom_items << {
      "key" => key,
      "label" => label.to_s.strip,
      "checked" => false,
      "required" => required,
      "category" => "custom",
      "created_by_id" => user&.id,
      "created_at" => Time.current.iso8601
    }
    save!
  end

  # Remove a custom item by key
  # @param key [String]
  # @return [Boolean] true if saved
  def remove_custom_item!(key)
    return false if custom_items.blank?
    before_size = custom_items.size
    self.custom_items = custom_items.reject { |i| i["key"] == key.to_s }
    return false if custom_items.size == before_size
    save!
  end

  def completion_percentage
    all = all_items_merged
    return 0 if all.empty?

    checked = all.count { |i| i["checked"] }
    (checked.to_f / all.size * 100).round
  end

  def ready_for_submission?
    all_required_complete
  end

  # Returns auto-detected items from the AutoDetector service.
  # These are NOT persisted — they're computed from current app state.
  # Memoized for the lifetime of the model instance so callbacks and views
  # that walk the items multiple times don't re-query the database.
  # @return [Array<Hash>] in the AutoDetector contract shape
  def auto_detected_items
    return [] unless listable && organization

    @auto_detected_items ||= ReleaseChecklist::AutoDetector.new(
      checklist: self,
      organization: organization,
      app: listable
    ).detect
  rescue StandardError => e
    Rails.logger.warn("ReleaseChecklist#auto_detected_items failed: #{e.class} - #{e.message}")
    []
  end

  # Returns ALL items: defaults + custom + auto-detected.
  # Use this for display and for completion calculations.
  def all_items_merged
    (items || []) + (custom_items || []) + auto_detected_items
  end

  def self.build_from_defaults(organization:, **attrs)
    new(
      organization: organization,
      items: DEFAULT_ITEMS.deep_dup,
      **attrs
    )
  end

  private

  def find_item(key)
    key_str = key.to_s
    (items || []).find { |i| i["key"] == key_str } ||
      (custom_items || []).find { |i| i["key"] == key_str }
  end

  def generate_custom_item_key(label)
    base = "custom_#{label.to_s.parameterize.gsub('-', '_').first(40)}"
    base = "custom_item" if base == "custom_" || base == "custom"
    # Append a counter if a custom item with this key already exists
    existing_keys = (custom_items || []).map { |i| i["key"] }
    key = base
    counter = 1
    while existing_keys.include?(key)
      key = "#{base}_#{counter}"
      counter += 1
    end
    key
  end

  def compute_all_required_complete
    # Auto-detected items are NOT counted in the denormalized
    # `all_required_complete` column because they're computed, not persisted.
    # The push guard in the controller separately checks for blocking
    # auto-detected issues at submit time.
    all = (items || []) + (custom_items || [])
    required = all.select { |i| i["required"] }
    self.all_required_complete = required.present? && required.all? { |i| i["checked"] }
  end

  def items_structure
    return if items.blank? || items == []

    unless items.is_a?(Array)
      errors.add(:items, "must be an array")
      return
    end

    items.each_with_index do |item, idx|
      unless item.is_a?(Hash) && item["key"].present? && item["label"].present?
        errors.add(:items, "item at index #{idx} must have 'key' and 'label'")
        return
      end
    end
  end
end
