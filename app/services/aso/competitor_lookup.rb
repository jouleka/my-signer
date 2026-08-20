module Aso
  # Fetches an App Store app's public metadata via iTunes Lookup so the
  # Suggestions tab can seed autocomplete from a competitor's app. Mirrors
  # Aso::KeywordSuggestions: Faraday 5s/3s, 24h Rails.cache, swallowed errors.
  class CompetitorLookup
    ENDPOINT = "https://itunes.apple.com/lookup".freeze
    TIMEOUT  = 5
    OPEN_TIMEOUT = 3
    CACHE_TTL = 24.hours
    STOPWORDS = Set.new(%w[
      the a an and or of in to for on with by at is as app pro lite free
    ]).freeze

    def initialize(app_id:, country: "us")
      @app_id = Integer(app_id, exception: false)
      @country = country.to_s.strip.downcase.first(2)
    end

    def fetch
      return nil unless @app_id && @app_id.between?(1, 9_999_999_999)

      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        fetch_from_apple
      end
    rescue StandardError => e
      Rails.logger.warn("Aso::CompetitorLookup failed: #{e.class} - #{e.message}")
      nil
    end

    private

    def cache_key
      "aso/competitor_lookup/#{@country}/#{@app_id}"
    end

    def fetch_from_apple
      conn = Faraday.new(url: ENDPOINT) do |f|
        f.options.timeout = TIMEOUT
        f.options.open_timeout = OPEN_TIMEOUT
      end
      response = conn.get do |req|
        req.params["id"] = @app_id
        req.params["country"] = @country
      end

      return nil unless response.success?

      parse(response.body)
    rescue Faraday::Error => e
      Rails.logger.warn("Aso::CompetitorLookup Apple request failed: #{e.message}")
      nil
    end

    def parse(body)
      data = JSON.parse(body)
      result = data["results"]&.first
      return nil unless result

      track_name  = result["trackName"].to_s
      description = result["description"].to_s

      {
        track_name:    track_name,
        primary_genre: result["primaryGenreName"],
        seller_name:   result["sellerName"],
        seed_terms:    derive_seed_terms(track_name, description)
      }
    rescue JSON::ParserError
      nil
    end

    def derive_seed_terms(track_name, description)
      tokens = []
      tokens.concat(tokenize(track_name))
      first_sentence = description.split(/[.!?]/).first.to_s
      tokens.concat(tokenize(first_sentence).first(5))
      tokens.uniq.reject { |t| t.length < 2 || STOPWORDS.include?(t) }
    end

    def tokenize(str)
      str.to_s.downcase.gsub(/[^\p{L}\p{N}\s-]/, " ").split(/[\s-]+/).reject(&:empty?)
    end
  end
end
