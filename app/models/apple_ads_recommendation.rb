class AppleAdsRecommendation < ApplicationRecord
  belongs_to :apple_app

  before_validation :normalize_keyword

  validates :keyword, presence: true, length: { maximum: 100 },
                      uniqueness: { scope: :apple_app_id }
  validates :search_popularity, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 5, less_than_or_equal_to: 100 }
  validates :search_popularity_updated_at, presence: true

  scope :most_popular, -> { order(search_popularity: :desc) }

  private

  def normalize_keyword
    return if keyword.blank?
    self.keyword = Aso::KeywordNormalizer.call(keyword)
  end
end
