require "jwt"
require "openssl"

module AppStoreConnect
  # The SINGLE ES256 signer for App Store Connect API JWTs (M-10).
  #
  # AppStoreConnect::Client#jwt delegates here so EVERY Apple API call funnels
  # through identical caching/TTL AND emits the 'asc_credential_used' audit
  # event on each cache miss. Do NOT add a second inline signer to Client.
  class JwtMinter
    JWT_TTL   = 14 * 60
    CACHE_TTL = 13 * 60

    def self.for(credential)
      EncryptedTokenCache.fetch("asc_jwt:#{credential.id}", expires_in: CACHE_TTL) do
        # Audit the credential USE on every cache miss (mysigner-30 follow-up).
        # Cache TTL is 13 minutes, so this fires ~5x/hour per credential —
        # enough granularity for breach forensics ("when was credential X
        # actually used to sign?") without flooding the audit table on
        # every API call within the cache window.
        Audit::Logger.log(
          organization: credential.organization,
          actor:        nil, # server-side mint; no human actor
          action:       "asc_credential_used",
          resource:     credential,
          metadata: {
            credential_id: credential.id,
            key_id:        credential.key_id,
            cache_miss:    true
          }
        )

        # Parse and assert the key is EC before signing. JWT.encode with ES256
        # would otherwise raise a less-actionable error (or, for some key types,
        # silently produce a token Apple rejects). Mirrors Client#jwt's guard.
        key = OpenSSL::PKey.read(credential.private_key)
        raise "Private key must be EC for ES256" unless key.is_a?(OpenSSL::PKey::EC)

        now = Time.now.to_i
        JWT.encode(
          {
            iss: credential.issuer_id,
            iat: now - 60,
            exp: now + JWT_TTL,
            aud: "appstoreconnect-v1"
          },
          key,
          "ES256",
          { kid: credential.key_id, typ: "JWT" }
        )
      end
    end
  end
end
