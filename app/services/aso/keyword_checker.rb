module Aso
  class KeywordChecker
    BASE_URL = "https://search.itunes.apple.com/WebObjects/MZStore.woa/wa/search".freeze

    def initialize(app:, keyword:, country:)
      @app, @keyword, @country = app, keyword, country
    end

    # Returns one of:
    #   :rate_limited                             — caller leaves tkc unchanged, retry tomorrow
    #   :network_error                            — same treatment, log
    #   { rank: Integer|nil, total_count: Integer } — caller writes rank + total_count
    def check
      response_json = fetch_search(@keyword, @country)
      return :rate_limited if response_json == :rate_limited
      return :network_error if response_json.nil?

      bubble = (response_json["bubbles"] || []).first || {}
      results = bubble["results"] || []
      total_count = bubble["totalCount"] || results.size

      # Empty bubble results = Apple soft-block (see spec audit C1/C2)
      return :rate_limited if results.empty?

      index = results.find_index { |r| r["id"].to_s == @app.app_store_id.to_s }
      { rank: index ? index + 1 : nil, total_count: total_count }
    end

    private

    # Returns the parsed JSON hash, nil on network error, or :rate_limited
    # if the rate limiter refused. Caches only successful non-empty responses.
    def fetch_search(kw, cc)
      cache_key = "aso/search_results/#{cc}/#{keyword_digest(kw)}"
      cached = Rails.cache.read(cache_key)
      return cached if cached

      return :rate_limited unless Aso::RateLimiter.acquire

      conn = Faraday.new(url: BASE_URL) do |f|
        f.options.timeout = 10
        f.options.open_timeout = 5
      end

      storefront = Aso::Storefronts.id_for(cc) || Aso::Storefronts::DEFAULT_ID
      resp = conn.get do |req|
        req.headers["X-Apple-Store-Front"] = "#{storefront},24 t:native"
        req.params["clientApplication"] = "Software"
        req.params["media"] = "software"
        req.params["term"] = Aso::KeywordNormalizer.call(kw)
        req.params["country"] = cc
      end

      return nil unless resp.success?

      body = JSON.parse(resp.body)
      bubbles = body["bubbles"] || []

      # Only cache real data — never cache empty/garbage
      if bubbles.any? && (bubbles.first["results"] || []).any?
        Rails.cache.write(cache_key, body, expires_in: 6.hours)
      end

      body
    rescue JSON::ParserError, Faraday::Error => e
      Rails.logger.warn(event: "aso.rank_check.parse_error", message: e.message)
      nil
    end

    def keyword_digest(kw)
      Digest::SHA256.hexdigest(Aso::KeywordNormalizer.call(kw))[0, 24]
    end
  end
end
