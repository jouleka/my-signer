# frozen_string_literal: true

# Encrypts minted bearer tokens / JWTs at rest in Rails.cache.
#
# WHY (M-5): Rails.cache is backed by Solid Cache — an UNENCRYPTED Postgres
# table. Caching raw access tokens / signed JWTs there means a DB dump (backup
# leak, read-replica access, SQL injection elsewhere) hands an attacker live
# Apple / Google API credentials with minutes-to-hours of validity left.
#
# This wrapper keeps the SAME cache keys (so existing eager-purge hooks like
# AppStoreConnectCredential#clear_token_cache, which call Rails.cache.delete
# with the bare key, keep working) but encrypts the VALUE with
# AES-256-GCM (AEAD) via ActiveSupport::MessageEncryptor. The key is derived
# from the app's secret_key_base through key_generator, so no new secret to
# manage and per-environment isolation is automatic.
#
# On any decrypt/verify failure (key rotation, corruption, tampering) the read
# is treated as a CACHE MISS: callers simply re-mint a fresh token. Tokens are
# cheap to regenerate and short-lived, so failing toward a re-mint is both safe
# and non-disruptive.
class EncryptedTokenCache
  # Distinct purpose string => distinct derived key. Bump only with care: a new
  # purpose silently invalidates every previously cached blob (all become cache
  # misses and re-mint), which is safe but causes a one-time mint stampede.
  KEY_PURPOSE = "asc/gp/ads token cache"
  KEY_LEN     = 32 # 256-bit key for AES-256-GCM
  CIPHER      = "aes-256-gcm"

  class << self
    # Read-through cache. Decrypts the stored blob; on miss OR decrypt failure
    # runs the block, encrypts the result, writes it (honoring expires_in), and
    # returns the freshly minted value.
    def fetch(key, expires_in: nil)
      existing = read(key)
      return existing unless existing.nil?

      value = yield
      write(key, value, expires_in: expires_in)
      value
    end

    # Returns the decrypted value, or nil on cache miss / decrypt failure.
    def read(key)
      blob = Rails.cache.read(key)
      # Treat nil (miss) AND any non-String (e.g. a legacy un-encrypted Hash
      # cached before this wrapper shipped) as a miss, so the "any failure =
      # re-mint" contract holds during the deploy window instead of raising
      # ArgumentError out of decrypt_and_verify.
      return nil unless blob.is_a?(String)

      encryptor.decrypt_and_verify(blob)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage,
           ActiveSupport::MessageVerifier::InvalidSignature
      # Tampered, corrupted, or encrypted under a rotated key. Treat as a miss
      # so the caller re-mints rather than blowing up.
      nil
    end

    # Encrypts the value and stores the opaque blob under the given key.
    def write(key, value, expires_in: nil)
      blob = encryptor.encrypt_and_sign(value)
      if expires_in.nil?
        Rails.cache.write(key, blob)
      else
        Rails.cache.write(key, blob, expires_in: expires_in)
      end
      value
    end

    def delete(key)
      Rails.cache.delete(key)
    end

    private

    def encryptor
      # Re-derived per call rather than memoized: the derived key depends on the
      # app's secret_key_base, and memoizing at class scope would pin a stale
      # key across credential/secret rotation within a long-lived process.
      secret = Rails.application.key_generator.generate_key(KEY_PURPOSE, KEY_LEN)
      # serializer: Marshal — the cached payloads are symbol-keyed Hashes holding
      # Time values (e.g. { access_token:, expires_at: }). The Rails 8 default
      # message serializer is JSON, which would silently coerce symbol keys to
      # strings and Time to String on read, so callers reading cached[:access_token]
      # would get nil and re-mint every call. Marshal preserves Ruby types exactly.
      # Safe here: decrypt_and_verify authenticates (AES-256-GCM) BEFORE
      # deserializing, so Marshal.load only ever runs on blobs we ourselves wrote.
      ActiveSupport::MessageEncryptor.new(secret, cipher: CIPHER, serializer: Marshal)
    end
  end
end
