# Canonical redactor for error messages that may carry credential material.
#
# This is the SINGLE source of truth for stripping secrets out of error
# strings before they are surfaced to end users (flash/JSON), persisted to
# *_credentials.last_sync_error columns, or written to sync-run tracking.
#
# It UNIONs every pattern that the three historical concern-level sanitizers
# applied independently (they had divergent rule sets, which let a secret slip
# through whichever redactor happened to miss it):
#
#   * SanitizesCredentialErrors (models)   — PEM, JSON secret fields
#     (escaped-quote aware), Bearer (broad charset), bare JWTs (eyJ...)
#   * SanitizesErrorMessage (jobs)         — Bearer, key=/token=/secret= kv,
#     PEM, file paths, query-string creds (?api_key=...)
#   * SanitizesApiErrors (controllers)     — same set as the jobs concern
#
# The three concerns now delegate here so all three apply the FULL union.
# Each concern keeps its own public method name/signature (back-compat) and
# may pass its own truncate length.
#
# Order matters: structured/high-entropy blocks (PEM, JSON fields, JWTs,
# Bearer) are redacted before the looser kv / query-string / path rules so
# the broad rules don't carve a secret block in half and leave a tail behind.
module ErrorMessageSanitizer
  module_function

  # @param error_or_string [Exception, String, nil]
  # @param max_length [Integer, nil] truncate the result to this many chars;
  #   pass nil to skip truncation (the model-level callers truncate separately).
  # @return [String, nil] nil only when the input was nil.
  def sanitize(error_or_string, max_length: nil)
    return nil if error_or_string.nil?

    msg =
      if error_or_string.respond_to?(:message)
        error_or_string.message.to_s
      else
        error_or_string.to_s
      end

    msg = redact(msg)
    msg = msg.truncate(max_length) if max_length
    msg
  end

  # Apply the full union of redaction rules to a plain string.
  # Exposed separately so callers that have already coerced to a String
  # (and manage their own truncation) can reuse it.
  def redact(msg)
    s = msg.to_s.dup

    # --- High-entropy / structured secret blocks first -------------------

    # PEM blocks (private keys, certs). Two historical forms are unioned:
    #   "-----BEGIN [^-]+-----...-----END [^-]+-----" (credential concern)
    #   "-----BEGIN[^-]*-----...-----END[^-]*-----"   (api/jobs concerns)
    # The api/jobs form is the superset (`[^-]*` allows the no-space header),
    # so use it. Emit the credential concern's token, which is the one specs
    # assert against.
    s = s.gsub(/-----BEGIN[^-]*-----.*?-----END[^-]*-----/m, "[REDACTED_PEM]")

    # JSON secret fields, e.g. "private_key":"...", "client_secret":"...".
    # `(?:[^"\\]|\\.)*` matches any non-quote/non-backslash char OR an escaped
    # character pair — so escaped quotes inside a JSON value (e.g. an inlined
    # PEM body or a nested service_account_json) don't prematurely close the
    # match and leave the tail of the secret unredacted.
    s = s.gsub(
      /"(private_key|private_key_id|service_account_json|keystore_password|key_password|client_email|client_id|client_secret|refresh_token|access_token)"\s*:\s*"(?:[^"\\]|\\.)*"/i,
      '"\1":"[REDACTED]"'
    )

    # Bearer tokens. Union of both charsets — the credential concern's broad
    # set ([A-Za-z0-9._~+/=-]) is a superset of the api/jobs `\S+`-ish form
    # for realistic tokens; use `\S+` so anything non-whitespace after the
    # scheme is caught.
    s = s.gsub(/\bBearer\s+\S+/i, "Bearer [REDACTED]")

    # Bare JWTs (header.payload.signature starting with the canonical eyJ).
    s = s.gsub(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/, "[REDACTED_JWT]")

    # --- Looser key/value and query-string credential forms --------------

    # Query-string credentials, e.g. ?api_key=..., &client_secret=...
    # Run before the generic key=/token=/secret= rules so the captured
    # parameter prefix is preserved (\1) rather than collapsed to "key=".
    s = s.gsub(
      /([?&][a-zA-Z_-]*(?:key|token|secret|auth|password|credential)[a-zA-Z_-]*=)[^\s&"']+/i,
      '\1[REDACTED]'
    )

    # Generic kv credential forms: key=..., token=..., secret=...
    # The `(?!\[REDACTED)` negative lookahead skips values that are already a bracketed
    # redaction placeholder (e.g. "[REDACTED_JWT]", "[REDACTED]" left by the
    # Bearer/JWT/query-string rules above) so these looser rules don't clobber
    # a more specific redaction and discard its surrounding context.
    s = s.gsub(/key[=:]\s*(?!\[REDACTED)\S+/i, "key=[REDACTED]")
    s = s.gsub(/token[=:]\s*(?!\[REDACTED)\S+/i, "token=[REDACTED]")
    s = s.gsub(/secret[=:]\s*(?!\[REDACTED)\S+/i, "secret=[REDACTED]")

    # --- File paths that could leak credential file locations ------------
    s = s.gsub(%r{/[\w./]+\.(?:rb|json|pem|key|p8|p12|env|yaml|yml)}, "[path]")

    s
  end
end
