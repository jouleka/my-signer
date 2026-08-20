# Shared error-message sanitization for credential-bearing models.
# Strips PEM blocks, Bearer tokens, bare JWTs, and JSON secret fields
# before errors are persisted to *_credentials.last_sync_error columns.
#
# Delegates to ErrorMessageSanitizer, the single canonical redactor, which
# UNIONs the rule sets that used to live divergently across this concern,
# SanitizesErrorMessage (jobs), and SanitizesApiErrors (controllers).
#
# Extracted from AppleAdsCredential#sanitize_error. Callers truncate the
# result themselves (column-specific lengths), so no truncation here; nil
# in still yields nil out.
module SanitizesCredentialErrors
  extend ActiveSupport::Concern

  private

  def sanitize_error(msg)
    ErrorMessageSanitizer.sanitize(msg)
  end
end
