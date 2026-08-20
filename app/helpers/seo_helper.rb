# frozen_string_literal: true

module SeoHelper
  SITE_NAME = "MySigner"
  DEFAULT_DESCRIPTION = "Ship iOS & Android apps from your terminal. One CLI to build, sign, and deploy to App Store and Google Play. No more wrestling with certificates, profiles, and store consoles."
  DEFAULT_HOST = "https://mysigner.dev"
  DEFAULT_OG_IMAGE = "/og-image.png"

  def page_title(title = nil)
    if title.present?
      "#{title} | #{SITE_NAME}"
    else
      "#{SITE_NAME} — Ship to App Stores from your terminal"
    end
  end

  def meta_description(description = nil)
    description.presence || DEFAULT_DESCRIPTION
  end

  def canonical_url(path = nil)
    "#{DEFAULT_HOST}#{path || request.path}"
  end

  def og_image_url(path = nil)
    "#{DEFAULT_HOST}#{path || DEFAULT_OG_IMAGE}"
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

  # JSON-LD WebSite schema with SearchAction — enables sitelinks search box in Google
  def website_json_ld
    tag.script(
      json_ld_payload({
        "@context": "https://schema.org",
        "@type": "WebSite",
        "name": SITE_NAME,
        "url": DEFAULT_HOST,
        "description": DEFAULT_DESCRIPTION,
        "potentialAction": {
          "@type": "SearchAction",
          "target": {
            "@type": "EntryPoint",
            "urlTemplate": "#{DEFAULT_HOST}/docs?q={search_term_string}"
          },
          "query-input": "required name=search_term_string"
        }
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
