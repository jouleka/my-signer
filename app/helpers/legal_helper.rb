module LegalHelper
  DEFAULT_BUSINESS_NAME = "MySigner".freeze
  DEFAULT_SUPPORT_EMAIL = "support@mysigner.dev".freeze

  # Per-document last-updated dates so editing one policy doesn't bump the
  # date on the other two. When you change a legal page, update its key here.
  LAST_UPDATED = {
    privacy: Date.new(2026, 5, 1),
    terms:   Date.new(2026, 5, 1),
    refund:  Date.new(2026, 5, 1)
  }.freeze

  # Default values used when the corresponding env var is not set. Governing
  # law / jurisdiction defaults are intentionally non-specific so the public
  # legal pages don't reveal where the operator is based. They still satisfy
  # the "Terms must name a governing law" requirement by pointing at the
  # Provider's principal place of business without naming the country.
  # When the operating entity is registered (or you decide to publish the
  # jurisdiction), override via env vars rather than editing here:
  #   LEGAL_ENTITY_NAME            e.g. "MySigner Sh.p.k." once registered
  #   LEGAL_GOVERNING_LAW          e.g. "the laws of England and Wales"
  #   LEGAL_GOVERNING_JURISDICTION e.g. "the courts of London, United Kingdom"
  DEFAULT_GOVERNING_LAW = "the laws applicable at the Provider's principal place of business".freeze
  DEFAULT_GOVERNING_JURISDICTION = "the competent courts at the Provider's principal place of business".freeze

  def legal_business_name
    ENV["LEGAL_BUSINESS_NAME"].presence || DEFAULT_BUSINESS_NAME
  end

  # The legal entity that owns the product. Defaults to the product name when
  # not configured — set LEGAL_ENTITY_NAME in production to the actual
  # registered entity (e.g., "MySigner Ltd.") to avoid circular phrasing.
  def legal_entity_name
    ENV["LEGAL_ENTITY_NAME"].presence || legal_business_name
  end

  def legal_support_email
    ENV["LEGAL_SUPPORT_EMAIL"].presence || DEFAULT_SUPPORT_EMAIL
  end

  def legal_governing_law
    ENV["LEGAL_GOVERNING_LAW"].presence || DEFAULT_GOVERNING_LAW
  end

  def legal_governing_jurisdiction
    ENV["LEGAL_GOVERNING_JURISDICTION"].presence || DEFAULT_GOVERNING_JURISDICTION
  end

  def legal_last_updated_label(document = nil)
    date = LAST_UPDATED.fetch(document) do
      LAST_UPDATED.values.max
    end
    date.strftime("%B %-d, %Y")
  end
end
