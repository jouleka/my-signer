class ScreenshotUpload < ApplicationRecord
  belongs_to :screenshot_project
  belongs_to :organization

  TARGETS = %w[app_store_connect google_play custom_product_page].freeze
  STATUSES = %w[pending in_progress completed failed].freeze

  validates :target, presence: true, inclusion: { in: TARGETS }
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc).limit(20) }
  scope :by_status, ->(status) { where(status: status) }
  scope :active, -> { where(status: %w[pending in_progress]) }
  scope :last_24_hours, -> { where("created_at >= ?", 24.hours.ago) }

  def self.daily_limit_for(organization)
    organization.entitlements.max_store_uploads_per_day_per_organization
  end

  def self.within_daily_limit?(organization_id, limit:)
    where(organization_id: organization_id).last_24_hours.count < limit
  end

  def self.active_for_project?(organization_id:, screenshot_project_id:)
    where(organization_id: organization_id, screenshot_project_id: screenshot_project_id).active.exists?
  end

  def pending?
    status == "pending"
  end

  def in_progress?
    status == "in_progress"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def mark_in_progress!
    update!(status: "in_progress", started_at: Time.current)
  end

  def mark_completed!
    update!(status: "completed", completed_at: Time.current)
  end

  def mark_failed!(error_message)
    with_lock do
      current_progress = reload.progress
      errors_list = current_progress["errors"] || []
      errors_list << error_message
      update!(status: "failed", completed_at: Time.current, progress: current_progress.merge("errors" => errors_list))
    end
  end

  def update_progress!(completed:, total:, current_file: nil, current_locale: nil)
    updates = { "completed" => completed, "total" => total, "current_file" => current_file }
    updates["current_locale"] = current_locale if current_locale
    update!(progress: progress.merge(updates))
  end
end
