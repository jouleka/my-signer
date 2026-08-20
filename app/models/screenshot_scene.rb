class ScreenshotScene < ApplicationRecord
  belongs_to :screenshot_project, counter_cache: :scenes_count

  has_one_attached :source_image

  validates :position, presence: true
  validate :has_image_data
  validates :source_image_content_type, inclusion: { in: %w[image/png image/jpeg] }, allow_blank: true
  validate :project_scene_limit, on: :create
  validate :ensure_project_plan_accessible, on: [ :create, :update ]
  validate :validate_locale_variants

  before_validation :auto_set_position, on: :create
  after_commit :invalidate_org_media_quota_cache, on: [ :create, :destroy ]

  # Returns true if image is stored via ActiveStorage
  def image_in_active_storage?
    source_image.attached?
  end

  # Unified image URL helper — prefers ActiveStorage, falls back to binary column
  def image_url(url_helpers: Rails.application.routes.url_helpers)
    if image_in_active_storage?
      url_helpers.rails_blob_path(source_image, only_path: true)
    else
      nil # controller handles binary serving via the `image` action
    end
  end

  def copy_to_project(target_project)
    if screenshot_project&.plan_frozen_on_current_plan?
      errors.add(:base, screenshot_project.plan_frozen_reason || "This screenshot project is frozen on the current plan.")
      return nil
    end

    if target_project.plan_frozen_on_current_plan?
      errors.add(:base, target_project.plan_frozen_reason || "Target screenshot project is frozen on the current plan.")
      return nil
    end

    target_project.organization.with_lock do
      target_project.lock!

      scene_limit = target_project.max_screenshot_scenes_per_project
      if target_project.screenshot_scenes.count >= scene_limit
        errors.add(:base, "Target project has reached the maximum of #{scene_limit} scenes")
        return nil
      end

      additional_media_bytes =
        if source_image.attached?
          source_image.blob.byte_size
        else
          source_image_data.to_s.bytesize
        end

      unless target_project.org_within_media_quota?(additional_media_bytes, use_cache: false)
        limit_label = ActiveSupport::NumberHelper.number_to_human_size(target_project.max_media_storage_bytes_per_organization)
        errors.add(:base, "Organization screenshot media quota exceeded (max #{limit_label})")
        return nil
      end

      new_scene = target_project.screenshot_scenes.new(
        caption_text: caption_text,
        subtitle_text: subtitle_text,
        overrides: overrides&.deep_dup || {},
        locale_variants: locale_variants&.deep_dup || {},
        source_image_content_type: source_image_content_type,
        source_image_filename: source_image_filename,
        source_image_width: source_image_width,
        source_image_height: source_image_height
      )

      if source_image.attached?
        # Share the same blob reference while still counting the copied scene toward org media limits.
        new_scene.source_image.attach(source_image.blob)
      elsif source_image_data.present?
        new_scene.source_image_data = source_image_data
      end

      new_scene.save ? new_scene : nil
    end
  end

  def caption_for_locale(locale)
    return caption_text if locale.blank?
    locale_variants&.dig(locale, "caption_text").presence || caption_text
  end

  def subtitle_for_locale(locale)
    return subtitle_text if locale.blank?
    locale_variants&.dig(locale, "subtitle_text").presence || subtitle_text
  end

  def set_locale_text(locale, caption: nil, subtitle: nil)
    self.locale_variants ||= {}
    self.locale_variants[locale] ||= {}
    self.locale_variants[locale]["caption_text"] = caption if caption
    self.locale_variants[locale]["subtitle_text"] = subtitle if subtitle
  end

  def effective_settings
    project_settings = screenshot_project.settings || {}
    project_settings.merge(overrides || {})
  end

  def custom_text_position?
    return false unless overrides.present?
    overrides.key?("text_position_x") && overrides.key?("text_position_y")
  end

  def text_position_x
    overrides&.dig("text_position_x")
  end

  def text_position_y
    overrides&.dig("text_position_y")
  end

  private

  def has_image_data
    return if source_image.attached? || source_image_data.present?
    errors.add(:base, "An image is required")
  end

  def project_scene_limit
    return unless screenshot_project
    limit = screenshot_project.max_screenshot_scenes_per_project
    if screenshot_project.screenshot_scenes.count >= limit
      errors.add(:base, "Project has reached the maximum of #{limit} scenes")
    end
  end

  def auto_set_position
    return if position.present?
    max_pos = screenshot_project.screenshot_scenes.maximum(:position) || 0
    self.position = max_pos + 1
  end

  def validate_locale_variants
    return if locale_variants.blank?

    if locale_variants.size > 50
      errors.add(:locale_variants, "cannot have more than 50 locales")
    end

    locale_variants.each do |locale, fields|
      next unless fields.is_a?(Hash)
      fields.each_value do |value|
        if value.is_a?(String) && value.length > 500
          errors.add(:locale_variants, "text values cannot exceed 500 characters")
          return
        end
      end
    end
  end

  def invalidate_org_media_quota_cache
    org_id = screenshot_project&.organization_id || ScreenshotProject.where(id: screenshot_project_id).pick(:organization_id)
    return if org_id.blank?

    ScreenshotProject.invalidate_media_quota_cache!(org_id)
  end

  def ensure_project_plan_accessible
    return unless screenshot_project&.plan_frozen_on_current_plan?

    errors.add(:base, screenshot_project.plan_frozen_reason || "This screenshot project is frozen on the current plan.")
  end
end
