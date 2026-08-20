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

  def build_urls
    urls = []

    # Landing page — highest priority, always fresh
    urls << { loc: @host, changefreq: "daily", priority: "1.0", lastmod: Date.today.to_s }

    # Documentation index
    urls << { loc: "#{@host}/docs", changefreq: "weekly", priority: "0.9", lastmod: latest_doc_modification.to_s }
    urls << { loc: "#{@host}/pricing", changefreq: "weekly", priority: "0.9" }

    # Documentation categories and pages
    DOCS_CATEGORIES.each do |slug, _category|
      dir = DOCS_CONTENT_PATH.join(slug)
      next unless Dir.exist?(dir)

      # Category page lastmod = most recent page in category
      category_mtime = Dir.glob(dir.join("*.md")).map { |f| File.mtime(f) }.max
      urls << { loc: "#{@host}/docs/#{slug}", changefreq: "weekly", priority: "0.8", lastmod: category_mtime&.strftime("%Y-%m-%d") }

      Dir.glob(dir.join("*.md")).each do |file|
        page_slug = File.basename(file, ".md")
        next if page_slug.start_with?("_")

        lastmod = File.mtime(file).strftime("%Y-%m-%d")
        # Guides and quickstart get higher priority (actionable content)
        priority = %w[guides quickstart].include?(slug) ? "0.8" : "0.7"
        urls << { loc: "#{@host}/docs/#{slug}/#{page_slug}", changefreq: "weekly", priority: priority, lastmod: lastmod }
      end
    end

    # Legal pages — low priority, rarely change
    urls << { loc: "#{@host}/terms-and-conditions", changefreq: "monthly", priority: "0.3" }
    urls << { loc: "#{@host}/privacy-policy", changefreq: "monthly", priority: "0.3" }
    urls << { loc: "#{@host}/refund-policy", changefreq: "monthly", priority: "0.3" }

    # Sign up page
    urls << { loc: "#{@host}/users/sign_up", changefreq: "monthly", priority: "0.6" }

    urls
  end

  def latest_doc_modification
    files = Dir.glob(DOCS_CONTENT_PATH.join("**/*.md"))
    files.map { |f| File.mtime(f) }.max&.strftime("%Y-%m-%d")
  end
end
