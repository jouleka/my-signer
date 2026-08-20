module Aso
  class LocaleKeywordMap
    # Apple's shared keyword search pools — keywords set for one locale in a group
    # apply to all locales in that group.
    APPLE_LOCALE_POOLS = [
      %w[en-US en-CA en-AU en-GB],
      %w[es-ES es-MX],
      %w[pt-BR pt-PT],
      %w[zh-Hans zh-Hant],
      %w[fr-FR fr-CA]
    ].freeze

    def initialize(apple_app:)
      @apple_app = apple_app
    end

    def build
      listings = StoreListing.where(listable: @apple_app).pluck(:locale, :keywords)
      keywords_by_locale = {}
      gaps = []

      listings.each do |locale, keywords_str|
        kw_array = parse_keywords(keywords_str)
        keywords_by_locale[locale] = kw_array
        gaps << locale if kw_array.empty?
      end

      {
        locales: keywords_by_locale.keys.sort,
        keywords_by_locale: keywords_by_locale,
        gaps: gaps,
        pool_groups: relevant_pool_groups(keywords_by_locale.keys),
        all_keywords: all_unique_keywords(keywords_by_locale)
      }
    end

    private

    def parse_keywords(str)
      return [] if str.blank?
      str.split(",").map(&:strip).reject(&:blank?)
    end

    def relevant_pool_groups(locales)
      APPLE_LOCALE_POOLS.select { |group| (group & locales).size > 1 }
    end

    def all_unique_keywords(keywords_by_locale)
      keywords_by_locale.values.flatten.map(&:downcase).uniq.sort
    end
  end
end
