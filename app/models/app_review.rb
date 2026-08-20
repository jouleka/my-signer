class AppReview < ApplicationRecord
  SENTIMENTS = %w[positive neutral negative].freeze
  REPLY_STATUSES = %w[none pending posted failed].freeze

  belongs_to :organization
  belongs_to :reviewable, polymorphic: true

  validates :remote_id, presence: true, uniqueness: { scope: %i[reviewable_type reviewable_id] }
  validates :rating, presence: true, inclusion: { in: 1..5 }
  validates :body, presence: true
  validates :reviewed_at, presence: true
  validates :sentiment, inclusion: { in: SENTIMENTS }, allow_nil: true
  validates :reply_status, inclusion: { in: REPLY_STATUSES }, allow_nil: true
  REPLY_CHAR_LIMITS = { "AppleApp" => 5970, "AndroidApp" => 350 }.freeze
  validates :reply_text, length: { maximum: ->(r) { r.reply_char_limit } }, allow_nil: true

  before_save :compute_sentiment

  scope :negative,   -> { where("rating <= 2") }
  scope :positive,   -> { where("rating >= 4") }
  scope :neutral,    -> { where(rating: 3) }
  scope :recent,     -> { order(reviewed_at: :desc) }
  scope :unanswered, -> { where(reply_status: "none") }

  scope :by_platform, ->(platform) {
    case platform.to_s
    when "apple", "ios"
      where(reviewable_type: "AppleApp")
    when "android", "google"
      where(reviewable_type: "AndroidApp")
    else
      all
    end
  }

  scope :by_sentiment, ->(sentiment) {
    return all if sentiment.blank?
    where(sentiment: sentiment.to_s)
  }

  scope :by_rating, ->(rating) {
    return all if rating.blank?
    where(rating: rating.to_i)
  }

  def platform
    case reviewable_type
    when "AppleApp" then :apple
    when "AndroidApp" then :android
    end
  end

  def apple?
    reviewable_type == "AppleApp"
  end

  def android?
    reviewable_type == "AndroidApp"
  end

  def replied?
    reply_status == "posted"
  end

  def reply_char_limit
    REPLY_CHAR_LIMITS.fetch(reviewable_type, 350)
  end

  private

  def compute_sentiment
    self.sentiment = ReviewSentiment.classify(rating: rating)
  end
end
