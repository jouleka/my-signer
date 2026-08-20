class SavedKeywordIdea < ApplicationRecord
  belongs_to :apple_app
  belongs_to :added_by_user, class_name: "User", optional: true

  before_validation :normalize_keyword

  validates :keyword, presence: true, length: { maximum: 100 },
                      uniqueness: { scope: :apple_app_id }

  private

  def normalize_keyword
    return if keyword.blank?
    self.keyword = Aso::KeywordNormalizer.call(keyword)
  end
end
