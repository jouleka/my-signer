require "jwt"

module Aso
  module AppleAds
    class Error < StandardError; end
    class CredentialsInvalid < Error; end
    class RateLimited < Error; end
    class TransientError < Error; end

    # OAuth2 + ES256 JWT client for Apple Search Ads Campaign Management API v5.
    #
    # Two tokens with DISTINCT lifecycles (do not conflate):
    #   1. client_assertion JWT — long-lived (up to 180d), signed with EC key,
    #      aud=https://appleid.apple.com, iss=sub=client_id
    #   2. access_token — short-lived (3600s), obtained by exchanging #1 via
    #      client_credentials grant at appleid.apple.com
    #
    # DO NOT copy AppStoreConnect::Client's JWT payload — ASC uses aud="appstoreconnect-v1"
    # and 15min TTL, which are wrong here. This is a different Apple product API.
    class Client
      API_HOST  = "https://api.searchads.apple.com".freeze
      API_PATH  = "/api/v5".freeze
      OAUTH_URL = "https://appleid.apple.com/auth/oauth2/token".freeze
      JWT_ALG   = "ES256".freeze
      # Apple permits client_assertion JWTs up to 180d, but rotating daily
      # caps the blast radius if the assertion ever leaks from a log or
      # cache-store dump. Signing is ~ms so the cost of daily rotation is
      # negligible. Cache TTL is set slightly shorter than JWT exp so we
      # never serve a JWT on the verge of expiring.
      JWT_TTL       = 1.day.to_i
      JWT_CACHE_TTL = JWT_TTL - 1.hour
      TOKEN_TTL     = 55.minutes  # conservative vs Apple's 3600s access_token
      HTTP_TIMEOUT  = 20          # seconds; applies to both @conn (API) and the OAuth token exchange

      def initialize(credential:)
        @credential = credential
        @conn = Faraday.new(url: API_HOST) do |f|
          # GET-only retry: retrying POSTs (campaign/adgroup creation) after a 502
          # can produce duplicate PAUSED scaffolds in the user's Apple Ads account.
          f.request :retry, max: 4, interval: 0.4, interval_randomness: 0.2, backoff_factor: 2,
                            retry_statuses: [ 429, 500, 502, 503, 504 ], methods: %i[get]
          f.options.timeout = HTTP_TIMEOUT
        end
      end

      def access_token
        # Encrypt the bearer access_token at rest in Rails.cache (M-5). On
        # decrypt failure EncryptedTokenCache treats it as a miss and re-mints.
        EncryptedTokenCache.fetch("aso/apple_ads/access_token/#{@credential.id}", expires_in: TOKEN_TTL) do
          fetch_access_token
        end
      end

      # Returns [{keyword:, search_popularity:, bid_amount_micros:}, ...]
      def recommended_keywords(app_store_id:)
        campaign_id, adgroup_id = ensure_campaign_adgroup(app_store_id: app_store_id)
        resp = authed_get("/campaigns/#{campaign_id}/adgroups/#{adgroup_id}/recommendations/keywords")
        body = JSON.parse(resp.body)

        (body.dig("data", "keywords") || []).map do |kw|
          {
            keyword: kw["text"].to_s.downcase.strip,
            search_popularity: kw["searchPopularity"],
            bid_amount_micros: parse_micros(kw.dig("suggestedMinBidAmount", "amount"))
          }
        end
      end

      private

      def fetch_access_token
        assertion = client_assertion_jwt
        resp = Faraday.post(OAUTH_URL) do |req|
          req.options.timeout = HTTP_TIMEOUT
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          req.body = URI.encode_www_form(
            grant_type: "client_credentials",
            client_id: @credential.client_id,
            client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
            client_assertion: assertion,
            scope: "searchadsorg"
          )
        end

        if [ 401, 403 ].include?(resp.status)
          # Parse just the OAuth "error" field — never echo the full body, which
          # could include a partial JWT or other sensitive context in debug responses.
          err = JSON.parse(resp.body)["error"] rescue "unknown"
          raise CredentialsInvalid, "OAuth #{resp.status} from Apple: #{err}"
        end
        raise RateLimited, "OAuth 429" if resp.status == 429
        raise TransientError, "OAuth #{resp.status}" unless resp.success?

        JSON.parse(resp.body).fetch("access_token")
      end

      def client_assertion_jwt
        # Encrypt the signed client_assertion JWT at rest in Rails.cache (M-5).
        EncryptedTokenCache.fetch("aso/apple_ads/assertion/#{@credential.id}", expires_in: JWT_CACHE_TTL) do
          # Audit on every cache miss (mysigner-30 follow-up). See parallel
          # comment in AppStoreConnect::JwtMinter for granularity rationale.
          Audit::Logger.log(
            organization: @credential.organization,
            actor:        nil,
            action:       "apple_ads_credential_used",
            resource:     @credential,
            metadata: {
              credential_id: @credential.id,
              client_id:     @credential.client_id,
              cache_miss:    true
            }
          )

          now = Time.current.to_i
          payload = {
            iss: @credential.client_id,
            sub: @credential.client_id,
            aud: "https://appleid.apple.com",
            iat: now,
            exp: now + JWT_TTL
          }
          headers = { kid: @credential.key_id, typ: "JWT" }
          key = begin
            OpenSSL::PKey.read(@credential.private_key_pem)
          rescue OpenSSL::OpenSSLError, ArgumentError
            raise CredentialsInvalid, "Could not parse EC private key"
          end
          JWT.encode(payload, key, JWT_ALG, headers)
        end
      end

      def full_path(path)
        "#{API_PATH}#{path.start_with?('/') ? path : "/#{path}"}"
      end

      def authed_get(path)
        resp = @conn.get(full_path(path)) do |req|
          req.headers["Authorization"] = "Bearer #{access_token}"
          req.headers["X-AP-Context"]  = "orgId=#{@credential.team_id}"
        end
        raise CredentialsInvalid, "401 from Apple Ads API" if resp.status == 401
        raise RateLimited, "429 from Apple Ads API" if resp.status == 429
        raise TransientError, "HTTP #{resp.status}" unless resp.success?
        resp
      end

      def authed_post(path, body)
        resp = @conn.post(full_path(path)) do |req|
          req.headers["Authorization"] = "Bearer #{access_token}"
          req.headers["X-AP-Context"]  = "orgId=#{@credential.team_id}"
          req.headers["Content-Type"]  = "application/json"
          req.body = JSON.generate(body)
        end
        raise CredentialsInvalid if resp.status == 401
        raise TransientError, "HTTP #{resp.status}" unless resp.success?
        resp
      end

      # Lazy paused campaign + ad group scaffold. Recommendations API requires
      # this scoping. Cached 7d per app to avoid re-creating every call.
      def ensure_campaign_adgroup(app_store_id:)
        cache_key = "aso/apple_ads/scaffold/#{@credential.id}/#{app_store_id}"
        Rails.cache.fetch(cache_key, expires_in: 7.days) do
          campaign_resp = authed_post("/campaigns", {
            name: "MySigner-Scaffold-#{app_store_id}",
            status: "PAUSED",
            adamId: app_store_id.to_i,
            budgetAmount: { amount: "1", currency: "USD" },
            dailyBudgetAmount: { amount: "1", currency: "USD" },
            countriesOrRegions: [ "US" ]
          })
          campaign_id = JSON.parse(campaign_resp.body).dig("data", "id")

          adgroup_resp = authed_post("/campaigns/#{campaign_id}/adgroups", {
            name: "scaffold",
            status: "PAUSED",
            defaultBidAmount: { amount: "0.50", currency: "USD" }
          })
          adgroup_id = JSON.parse(adgroup_resp.body).dig("data", "id")

          [ campaign_id, adgroup_id ]
        end
      end

      def parse_micros(amount_str)
        return nil if amount_str.to_s.strip.empty?
        (amount_str.to_f * 1_000_000).round
      end
    end
  end
end
