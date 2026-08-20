class AppAnalyticsSnapshot < ApplicationRecord
  belongs_to :organization
  belongs_to :snapshotable, polymorphic: true

  validates :snapshot_date, presence: true,
    uniqueness: { scope: [ :snapshotable_type, :snapshotable_id ] }
  validates :first_time_downloads, :redownloads, :total_downloads,
    :impressions, :product_page_views, :updates, :sessions,
    :active_devices, :crashes,
    numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :recent, -> { order(snapshot_date: :desc) }
  scope :last_n_days, ->(n) { where("snapshot_date >= ?", n.days.ago.to_date) }
  scope :for_date_range, ->(start_date, end_date) {
    where(snapshot_date: start_date..end_date)
  }

  def apple?
    snapshotable_type == "AppleApp"
  end

  def android?
    snapshotable_type == "AndroidApp"
  end

  def computed_conversion_rate
    return 0.0 if impressions.to_i.zero?
    (total_downloads.to_f / impressions * 100).round(2)
  end
end
