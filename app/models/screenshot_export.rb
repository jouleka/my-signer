class ScreenshotExport < ApplicationRecord
  belongs_to :screenshot_project

  has_one_attached :image

  validates :resolution, presence: true
  validates :scene_position, presence: true
  validates :export_format, inclusion: { in: %w[standard fastlane] }

  scope :for_resolution, ->(res) { where(resolution: res) }
  scope :for_locale, ->(locale) { where(locale: locale.presence || "") }
  scope :fastlane, -> { where(export_format: "fastlane") }
  scope :standard, -> { where(export_format: "standard") }

  # Upsert an export image via ActiveStorage.
  # Returns the ScreenshotExport record.
  def self.upsert_export!(project:, resolution:, scene_position:, locale: nil, image_data:, export_format: "standard")
    record = project.screenshot_exports.find_or_initialize_by(
      resolution: resolution,
      scene_position: scene_position,
      locale: locale.presence || ""
    )
    record.export_format = export_format
    record.image.attach(
      io: StringIO.new(image_data),
      filename: "screenshot_#{scene_position.to_s.rjust(2, '0')}.png",
      content_type: "image/png"
    )
    record.save!
    record
  rescue ActiveRecord::RecordNotUnique
    record = project.screenshot_exports.find_by!(
      resolution: resolution,
      scene_position: scene_position,
      locale: locale.presence || ""
    )
    record.export_format = export_format
    record.image.attach(
      io: StringIO.new(image_data),
      filename: "screenshot_#{scene_position.to_s.rjust(2, '0')}.png",
      content_type: "image/png"
    )
    record.save!
    record
  end

  # Total ActiveStorage bytes for exports belonging to a given organization.
  def self.org_cloud_export_storage_bytes(organization_id)
    ActiveStorage::Attachment
      .joins(:blob)
      .joins("INNER JOIN screenshot_exports ON screenshot_exports.id = active_storage_attachments.record_id")
      .joins("INNER JOIN screenshot_projects ON screenshot_projects.id = screenshot_exports.screenshot_project_id")
      .where(active_storage_attachments: { record_type: "ScreenshotExport", name: "image" })
      .where(screenshot_projects: { organization_id: organization_id })
      .sum("active_storage_blobs.byte_size")
  end
end
