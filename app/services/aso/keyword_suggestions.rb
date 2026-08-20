module Aso
  class KeywordSuggestions
    ENDPOINT = "https://search.itunes.apple.com/WebObjects/MZSearchHints.woa/wa/hints".freeze

    # Apple requires an X-Apple-Store-Front header or it returns an empty hints
    # array. The URL `country` param selects the locale of the results, so a
    # single storefront works for every country.
    STOREFRONT = "143441-1,29".freeze

    def initialize(term:, country: "us")
      @term = term.to_s.strip.first(100)
      @country = country.to_s.strip.downcase.first(2)
    end

    def fetch
      return [] if @term.blank?

      cache_key = "aso/suggestions/#{@country}/#{@term.downcase}"
      Rails.cache.fetch(cache_key, expires_in: 1.hour) do
        fetch_from_apple
      end
    rescue StandardError => e
      Rails.logger.warn("Aso::KeywordSuggestions failed: #{e.class} - #{e.message}")
      []
    end

    private

    def fetch_from_apple
      conn = Faraday.new(url: ENDPOINT) do |f|
        f.options.timeout = 5
        f.options.open_timeout = 3
      end

      response = conn.get do |req|
        req.headers["X-Apple-Store-Front"] = STOREFRONT
        req.params["clientApplication"] = "Software"
        req.params["term"] = @term
        req.params["country"] = @country
      end

      return [] unless response.success?

      parse_hints(response.body)
    rescue Faraday::Error => e
      Rails.logger.warn("Aso::KeywordSuggestions Apple request failed: #{e.message}")
      []
    end

    # Apple returns an XML plist. Extract the <string> that immediately follows
    # each <key>term</key> inside the hints <array>.
    def parse_hints(body)
      doc = Nokogiri::XML(body)
      doc.xpath("//array/dict").filter_map do |dict|
        term_key = dict.xpath("./key[text()='term']").first
        next unless term_key
        term_key.xpath("./following-sibling::string[1]").first&.text
      end.uniq
    rescue Nokogiri::XML::SyntaxError => e
      Rails.logger.warn("Aso::KeywordSuggestions plist parse failed: #{e.message}")
      []
    end
  end
end
