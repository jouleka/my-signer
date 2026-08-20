require "googleauth"
require "stringio"

module GooglePlay
  class TokenMinter
    SCOPE             = "https://www.googleapis.com/auth/androidpublisher"
    CACHE_TTL         = 55.minutes
    EXPIRY_SAFETY_PAD = 60.seconds

    # Returns { access_token:, expires_at:, client_email:, developer_account_id:, cache_hit: }
    def self.mint(credential)
      cache_key = "gp_access_token:#{credential.id}"
      # Tokens are encrypted at rest in Rails.cache (Solid Cache = unencrypted
      # Postgres). On decrypt failure EncryptedTokenCache.read returns nil, so
      # we transparently fall through to a fresh mint (M-5).
      cached = EncryptedTokenCache.read(cache_key)
      return cached.merge(cache_hit: true) if cached

      sa = JSON.parse(credential.service_account_json)
      creds = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(credential.service_account_json),
        scope: SCOPE
      )
      creds.fetch_access_token!

      payload = {
        access_token:         creds.access_token,
        expires_at:           creds.expires_at,
        client_email:         sa["client_email"],
        developer_account_id: credential.developer_account_id
      }

      # Clamp the cache TTL to Google's own expiry minus a 60s safety pad.
      # Without this, a token minted near its expiry could be served from
      # cache for up to 55m and then be rejected by Google as expired.
      ttl = cache_ttl_for(creds.expires_at)
      EncryptedTokenCache.write(cache_key, payload, expires_in: ttl) if ttl.positive?
      payload.merge(cache_hit: false)
    end

    def self.cache_ttl_for(expires_at)
      return CACHE_TTL if expires_at.nil?

      remaining = expires_at.to_i - Time.now.to_i - EXPIRY_SAFETY_PAD.to_i
      [ CACHE_TTL.to_i, remaining ].min.seconds
    end
    private_class_method :cache_ttl_for
  end
end
