class ReviewSentiment
  # Simple rule-based sentiment classification from star rating.
  # 1-2 stars = negative, 3 = neutral, 4-5 = positive.
  def self.classify(rating:)
    case rating.to_i
    when 1, 2 then "negative"
    when 3    then "neutral"
    when 4, 5 then "positive"
    else "neutral"
    end
  end
end
