class ReviewResponseTemplate < ApplicationRecord
  CATEGORIES = %w[bug_report feature_request praise complaint general].freeze

  belongs_to :organization

  validates :name, presence: true
  validates :body, presence: true, length: { maximum: 350 }
  validates :category, inclusion: { in: CATEGORIES }

  scope :ordered, -> { order(position: :asc, created_at: :asc) }
  scope :by_category, ->(cat) { cat.present? ? where(category: cat) : all }
end
