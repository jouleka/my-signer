module PaddleRedirectSafety
  extend ActiveSupport::Concern

  PADDLE_ID_PREFIXES = %w[sub pri txn ctm inv adj add biz dsc ntf rpt cus].freeze

  included do
    private

    # Accepts an optional candidate URL (usually params[:return_to] or a
    # cached referer). Returns a same-origin path, or pricing_path when the
    # candidate is absent, malformed, cross-origin, or protocol-relative.
    #
    # Protects against open redirects that would let an attacker seed
    # return_to / referer to bounce a logged-in user to a lookalike domain.
    def safe_redirect_path(candidate = nil)
      candidate = candidate.presence || request.referer
      return pricing_path if candidate.blank?

      uri = URI.parse(candidate.to_s)

      if uri.host.present?
        return pricing_path unless uri.host == request.host && uri.port == request.port
      end

      # URI::Generic (a bare path like "/billing") doesn't define #request_uri;
      # only URI::HTTP does. Build the path+query manually so both shapes work.
      path = uri.path.to_s
      path += "?#{uri.query}" if uri.query.present?

      # Reject protocol-relative URLs ("//evil.com/x") — they are treated as
      # absolute by browsers and would bypass the host check above.
      return pricing_path if path.start_with?("//")
      return pricing_path unless path.start_with?("/")

      path
    rescue URI::InvalidURIError
      pricing_path
    end

    # Strips Paddle's internal IDs from error messages before exposing them
    # in a flash. Covers the ID prefixes Paddle's API actually emits — missed
    # prefixes leak internal state. Keep in sync with Paddle's API reference
    # whenever new resource ID shapes are introduced.
    def sanitize_paddle_error(message, fallback:)
      return fallback if message.blank?

      pattern = /\b(#{PADDLE_ID_PREFIXES.join('|')})_[A-Za-z0-9]+\b/
      message.to_s.gsub(pattern, "[redacted]").presence || fallback
    end
  end
end
