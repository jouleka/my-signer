# frozen_string_literal: true

module SeoHelper
  SITE_NAME = "MySigner"
  DEFAULT_DESCRIPTION = "Ship iOS & Android apps from your terminal. One CLI to build, sign, and deploy to App Store and Google Play. No more wrestling with certificates, profiles, and store consoles."
  DEFAULT_HOST = "https://mysigner.dev"
  DEFAULT_OG_IMAGE = "/og-image.png"

  # Controllers whose pages are public marketing/docs content and may be
  # indexed. Everything else (devise, onboarding, dashboard, settings, ...)
  # gets a robots noindex meta tag.
  INDEXABLE_CONTROLLERS = %w[landing docs pricing legal].freeze

  def page_title(title = nil)
    title = seo_plain_text(title)
    if title.present?
      "#{title} | #{SITE_NAME}"
    else
      "#{SITE_NAME} — Ship to App Stores from your terminal"
    end
  end

  def meta_description(description = nil)
    seo_plain_text(description).presence || DEFAULT_DESCRIPTION
  end

  # Always the apex host, never www, no query string, no trailing slash
  # (except the root path itself).
  def canonical_url(path = nil)
    path = (path || request.path).to_s
    path = path.chomp("/") while path.length > 1 && path.end_with?("/")
    "#{DEFAULT_HOST}#{path}"
  end

  def og_image_url(path = nil)
    "#{DEFAULT_HOST}#{path || DEFAULT_OG_IMAGE}"
  end

  # Content for <meta name="robots">, or nil when the page may be indexed.
  # Signed-in views are personalized, and auth/app pages have no search value.
  def robots_meta_content
    return "noindex, nofollow" if user_signed_in?
    return "noindex" if content_for?(:noindex)
    return nil if INDEXABLE_CONTROLLERS.include?(controller_path) && response.status == 200

    "noindex"
  end

  # JSON-LD BreadcrumbList schema — Google shows breadcrumbs in search results
  # Usage: breadcrumb_json_ld([{ name: "Docs", url: "/docs" }, { name: "Commands", url: "/docs/commands" }])
  def breadcrumb_json_ld(items)
    list_items = items.each_with_index.map do |item, i|
      {
        "@type": "ListItem",
        "position": i + 1,
        "name": item[:name],
        "item": item[:url] ? "#{DEFAULT_HOST}#{item[:url]}" : nil
      }.compact
    end

    tag.script(
      json_ld_payload({ "@context": "https://schema.org", "@type": "BreadcrumbList", "itemListElement": list_items }),
      type: "application/ld+json"
    )
  end

  # JSON-LD WebSite schema. No SearchAction: the docs search is a client-side
  # modal and does not read a ?q= parameter.
  def website_json_ld
    tag.script(
      json_ld_payload({
        "@context": "https://schema.org",
        "@type": "WebSite",
        "@id": "#{DEFAULT_HOST}/#website",
        "name": SITE_NAME,
        "url": "#{DEFAULT_HOST}/",
        "description": DEFAULT_DESCRIPTION,
        "inLanguage": "en",
        "publisher": { "@id": "#{DEFAULT_HOST}/#organization" }
      }),
      type: "application/ld+json"
    )
  end

  # JSON-LD Organization schema.
  def organization_json_ld
    tag.script(
      json_ld_payload({
        "@context": "https://schema.org",
        "@type": "Organization",
        "@id": "#{DEFAULT_HOST}/#organization",
        "name": SITE_NAME,
        "url": "#{DEFAULT_HOST}/",
        "logo": "#{DEFAULT_HOST}/icon.png",
        "email": SUPPORT_EMAIL
      }),
      type: "application/ld+json"
    )
  end

  # JSON-LD SoftwareApplication schema with offers taken from the real plan
  # catalog (Free + Billing::PlanCatalog), so prices never drift.
  def software_application_json_ld(description: nil)
    tag.script(
      json_ld_payload({
        "@context": "https://schema.org",
        "@type": "SoftwareApplication",
        "@id": "#{DEFAULT_HOST}/#software",
        "name": SITE_NAME,
        "description": seo_plain_text(description).presence || DEFAULT_DESCRIPTION,
        "url": "#{DEFAULT_HOST}/",
        "applicationCategory": "DeveloperApplication",
        "applicationSubCategory": "Mobile app build, code signing and release automation",
        # The CLI is a Ruby gem: macOS is required for iOS builds, Android
        # builds and store uploads also run on Linux/Windows (see docs).
        "operatingSystem": "macOS, Linux, Windows",
        "softwareVersion": MySigner::CLI_VERSION,
        "publisher": { "@id": "#{DEFAULT_HOST}/#organization" },
        "offers": software_offers
      }),
      type: "application/ld+json"
    )
  end

  # JSON-LD TechArticle schema — helps Google understand documentation pages
  def tech_article_json_ld(title:, description:, url:, category:, date_modified: nil)
    data = {
      "@context": "https://schema.org",
      "@type": "TechArticle",
      "headline": title,
      "description": description,
      "url": "#{DEFAULT_HOST}#{url}",
      "author": { "@type": "Organization", "name": SITE_NAME, "url": DEFAULT_HOST },
      "publisher": { "@type": "Organization", "name": SITE_NAME, "url": DEFAULT_HOST, "logo": { "@type": "ImageObject", "url": "#{DEFAULT_HOST}/og-image.png" } },
      "mainEntityOfPage": { "@type": "WebPage", "@id": "#{DEFAULT_HOST}#{url}" },
      "articleSection": category,
      "inLanguage": "en"
    }
    data["dateModified"] = date_modified.strftime("%Y-%m-%d") if date_modified
    data["datePublished"] = date_modified.strftime("%Y-%m-%d") if date_modified

    tag.script(json_ld_payload(data), type: "application/ld+json")
  end

  # JSON-LD HowTo schema — for step-by-step guide pages
  def howto_json_ld(title:, description:, steps:)
    data = {
      "@context": "https://schema.org",
      "@type": "HowTo",
      "name": title,
      "description": description,
      "step": steps.each_with_index.map { |step, i|
        { "@type": "HowToStep", "position": i + 1, "name": step[:name], "text": step[:text] }
      }
    }
    tag.script(json_ld_payload(data), type: "application/ld+json")
  end

  # JSON-LD FAQPage schema — for FAQ content
  def faq_json_ld(questions)
    data = {
      "@context": "https://schema.org",
      "@type": "FAQPage",
      "mainEntity": questions.map { |q|
        {
          "@type": "Question",
          "name": q[:question],
          "acceptedAnswer": { "@type": "Answer", "text": q[:answer] }
        }
      }
    }
    tag.script(json_ld_payload(data), type: "application/ld+json")
  end

  private

  SUPPORT_EMAIL = "support@mysigner.dev"
  BILLING_DURATIONS = { "monthly" => "P1M", "yearly" => "P1Y" }.freeze

  def software_offers
    pricing = "#{DEFAULT_HOST}/pricing"
    free = { "@type": "Offer", "name": "Free", "price": "0", "priceCurrency": "USD", "url": pricing }

    paid = Billing::PlanCatalog::PLANS.flat_map do |_tier, intervals|
      intervals.map do |interval, plan|
        price = format("%.2f", plan[:price])
        {
          "@type": "Offer",
          "name": "#{SITE_NAME} #{plan[:label]}",
          "price": price,
          "priceCurrency": plan[:currency],
          "url": pricing,
          "priceSpecification": {
            "@type": "UnitPriceSpecification",
            "price": price,
            "priceCurrency": plan[:currency],
            "billingDuration": BILLING_DURATIONS.fetch(interval),
            "unitText": plan[:interval_label]
          }
        }
      end
    end

    [ free, *paid ]
  end

  # content_for blocks are captured as HTML-escaped SafeBuffers ("&" becomes
  # "&amp;"). Interpolating that into a plain String and printing it with
  # <%= %> escaped it a second time ("&amp;amp;" in the live <title>), and
  # to_json leaked the entity into JSON-LD. Normalize to plain text so the
  # value is escaped exactly once by whatever renders it.
  def seo_plain_text(value)
    return "" if value.nil?

    text = value.to_s
    text = CGI.unescapeHTML(text) if value.html_safe?
    text.squish
  end

  # Serialize a JSON-LD payload for safe embedding inside a <script> element.
  #
  # `to_json` alone does not escape `<`, `>` or `&`, so a value containing the
  # literal string "</script>" would break out of the script element (a stored
  # XSS vector). `json_escape` (ERB::Util.json_escape) escapes those characters
  # to their unicode equivalents, which JSON parsers treat identically — so
  # there is no behavior change for normal data — while preventing the breakout.
  def json_ld_payload(data)
    json_escape(data.to_json).html_safe
  end
end
