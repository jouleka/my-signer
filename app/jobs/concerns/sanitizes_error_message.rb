module SanitizesErrorMessage
  extend ActiveSupport::Concern

  private

  # Redacts credentials/tokens/paths from an error message so it's safe to
  # surface to end users or persist to the DB. Accepts either an exception
  # or a String.
  #
  # Delegates to ErrorMessageSanitizer, the single canonical redactor that
  # UNIONs every pattern the three historical sanitizers applied. This
  # concern keeps its own 500-char truncation for back-compat.
  def sanitize_error_message(error_or_string)
    ErrorMessageSanitizer.sanitize(error_or_string, max_length: 500).to_s
  end
end
