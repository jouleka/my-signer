module SanitizesApiErrors
  extend ActiveSupport::Concern

  private

  # Redacts credentials/tokens/paths from an error message so it's safe to
  # surface to end users in flash alerts or JSON responses.
  #
  # Delegates to ErrorMessageSanitizer, the single canonical redactor that
  # UNIONs every pattern the three historical sanitizers applied. This
  # concern keeps its own default 300-char truncation for back-compat.
  def safe_error_message(error_or_string, max_length: 300)
    ErrorMessageSanitizer.sanitize(error_or_string, max_length: max_length).to_s
  end
end
