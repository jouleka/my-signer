# frozen_string_literal: true

class SitemapController < ActionController::Base
  DOCS_CONTENT_PATH = Rails.root.join("app/views/docs/content")
  DOCS_CATEGORIES = DocsController::CATEGORIES

  def show
    @host = "https://mysigner.dev"
    @urls = build_urls
    # Cache sitemap for 1 hour, revalidate
    response.headers["Cache-Control"] = "public, max-age=3600, must-revalidate"
    respond_to do |format|
      format.xml
    end
  end

  private

  # Only public, indexable, 200-status URLs. Auth (devise) and app pages are
  # deliberately excluded; they carry a robots noindex meta tag.
  def build_urls
    urls = []

    # Landing page. No lastmod: it has no reliable modification date, and a
    # lastmod that changes on every request teaches Google to ignore it.
    urls << { loc: "#{@host}/", changefreq: "weekly", priority: "1.0" }

    # Documentation index
    urls << { loc: "#{@host}/docs", changefreq: "weekly", priority: "0.9", lastmod: latest_doc_modification }
    urls << { loc: "#{@host}/pricing", changefreq: "weekly", priority: "0.9" }

    # Documentation categories and pages
    DOCS_CATEGORIES.each_key do |slug|
      dir = DOCS_CONTENT_PATH.join(slug)
      next unless Dir.exist?(dir)

      pages = doc_files(dir).map { |file| [ file, doc_lastmod(file) ] }

      # Category page lastmod = most recent page in category
      urls << { loc: "#{@host}/docs/#{slug}", changefreq: "weekly", priority: "0.8", lastmod: pages.map(&:last).max&.strftime("%Y-%m-%d") }

      pages.each do |file, lastmod|
        page_slug = File.basename(file, ".md")
        # Guides and quickstart get higher priority (actionable content)
        priority = %w[guides quickstart].include?(slug) ? "0.8" : "0.7"
        urls << { loc: "#{@host}/docs/#{slug}/#{page_slug}", changefreq: "weekly", priority: priority, lastmod: lastmod.strftime("%Y-%m-%d") }
      end
    end

    # Legal / trust pages — low priority, rarely change
    urls << { loc: "#{@host}/security", changefreq: "monthly", priority: "0.4" }
    urls << { loc: "#{@host}/terms-and-conditions", changefreq: "monthly", priority: "0.3" }
    urls << { loc: "#{@host}/privacy-policy", changefreq: "monthly", priority: "0.3" }
    urls << { loc: "#{@host}/refund-policy", changefreq: "monthly", priority: "0.3" }

    urls
  end

  # Underscore-prefixed files (_index.md) are partials, not pages.
  def doc_files(dir)
    Dir.glob(dir.join("*.md")).reject { |file| File.basename(file).start_with?("_") }.sort
  end

  def doc_lastmod(file)
    DocsController.last_modified(DocsController.frontmatter_for(file), file)
  end

  def latest_doc_modification
    files = DOCS_CATEGORIES.keys.flat_map do |slug|
      dir = DOCS_CONTENT_PATH.join(slug)
      Dir.exist?(dir) ? doc_files(dir) : []
    end
    files.map { |f| doc_lastmod(f) }.max&.strftime("%Y-%m-%d")
  end
end
