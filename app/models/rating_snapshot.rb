class RatingSnapshot < ApplicationRecord
  belongs_to :organization
  belongs_to :snapshotable, polymorphic: true

  validates :snapshot_date, presence: true, uniqueness: { scope: %i[snapshotable_type snapshotable_id] }
  validates :average_rating, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }

  scope :recent, -> { order(snapshot_date: :desc) }
  scope :last_n_days, ->(n) { where("snapshot_date >= ?", n.days.ago.to_date) }
end
