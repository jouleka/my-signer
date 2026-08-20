module Aso
  module KeywordNormalizer
    # Canonical keyword normalization used wherever keywords are compared,
    # stored, or looked up. NFC (Unicode), downcase, strip, collapse whitespace.
    # Must stay in sync across TrackedKeyword, AppleAdsRecommendation,
    # KeywordChecker (cache key), and KeywordRanking (backfill resolver).
    def self.call(keyword)
      return "" if keyword.nil?
      keyword.to_s.unicode_normalize(:nfc).downcase.strip.gsub(/\s+/, " ")
    end
  end
end
