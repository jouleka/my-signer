class PlayStoreRelease < ApplicationRecord
  belongs_to :android_app

  TRACKS = %w[internal alpha beta production].freeze
  STATUSES = %w[draft submitted live rejected removed].freeze

  before_validation :squish_fields

  validates :track, inclusion: { in: TRACKS }
  validates :status, inclusion: { in: STATUSES }
  validates :version_code, presence: true
  validates :user_fraction, numericality: { greater_than: 0.0, less_than_or_equal_to: 1.0 }, allow_nil: true
  validates :auto_submit, inclusion: { in: [ true, false ] }

  scope :recent, -> { order(Arel.sql("COALESCE(released_at, created_at) DESC")) }
  scope :with_status, ->(status) { status.present? ? where(status: status) : all }
  scope :for_version, ->(version_code) { where(version_code: version_code) }

  after_update :notify_status_change, if: :saved_change_to_status?

  def effective_released_at
    released_at || updated_at
  end

  private

  def notify_status_change
    ReleaseEvents::Notifier.notify_android_state_change(self)
  rescue StandardError => e
    Rails.logger.error("PlayStoreRelease#notify_status_change failed: #{e.class} - #{e.message}")
  end

  def squish_fields
    self.track = track.to_s.strip
    self.status_url = status_url.to_s.strip
    self.status = status.to_s.strip.downcase.presence || "draft"
    self.version_code = version_code.to_s.strip
  end
end
