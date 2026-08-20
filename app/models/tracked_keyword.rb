class TrackedKeyword < ApplicationRecord
  belongs_to :apple_app
  has_many :tracked_keyword_countries, dependent: :destroy

  VALID_POPULARITY_SOURCES = %w[apple_ads_recommendations].freeze

  before_validation :normalize_keyword

  validates :keyword, presence: true, length: { maximum: 100 },
                      uniqueness: { scope: :apple_app_id }
  validates :search_popularity_source, inclusion: { in: VALID_POPULARITY_SOURCES }
  validates :search_popularity, numericality: {
    only_integer: true, greater_than_or_equal_to: 5, less_than_or_equal_to: 100
  }, allow_nil: true

  private

  def normalize_keyword
    return if keyword.blank?
    self.keyword = Aso::KeywordNormalizer.call(keyword)
  end
end
