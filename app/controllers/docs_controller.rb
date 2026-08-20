# frozen_string_literal: true

require "redcarpet"
require "rouge"
require "rouge/plugins/redcarpet"

class DocsController < ApplicationController
  # Documentation is public - no authentication required
  # Allow public caching for search engine crawlers
  before_action :set_public_cache_headers

  CONTENT_PATH = Rails.root.join("app/views/docs/content")
  CATEGORIES = {
    "quickstart" => { title: "Quickstart", icon: "fa-solid fa-bolt", description: "Get started in 5 minutes" },
    "commands" => { title: "Commands", icon: "fa-solid fa-list-check", description: "CLI command reference" },
    "guides" => { title: "Guides", icon: "fa-solid fa-route", description: "Step-by-step tutorials" },
    "dashboard" => { title: "Dashboard", icon: "fa-solid fa-gauge-high", description: "Web dashboard documentation" },
    "blog" => { title: "Articles", icon: "fa-solid fa-pen-nib", description: "How-tos, deep dives, and lessons learned" },
    "compare" => { title: "Compare", icon: "fa-solid fa-scale-balanced", description: "Honest comparisons with other mobile release tools" }
  }.freeze

  def index
    @categories = CATEGORIES
  end

  def category
    @category_slug = params[:category]
    @category = CATEGORIES[@category_slug]
    return render_not_found unless @category

    @pages = category_pages(@category_slug)
  end

  def show
    @category_slug = params[:category]
    @slug = params[:slug]
    @category = CATEGORIES[@category_slug]
    return render_not_found unless @category

    file_path = doc_file_path(@category_slug, @slug)
    return render_not_found unless file_path && File.exist?(file_path)

    raw_content = File.read(file_path)
    raw_content = raw_content.gsub("{{cli_version}}", MySigner::CLI_VERSION)
    @frontmatter, markdown_content = parse_frontmatter(raw_content)
    @title = @frontmatter["title"] || @slug.titleize
    @content = render_markdown(markdown_content)
    @toc = generate_toc(markdown_content)
    @pages = category_pages(@category_slug)
    @prev_page, @next_page = find_adjacent_pages(@slug)
    @file_mtime = File.mtime(file_path)
    @related_pages = find_related_pages(@category_slug, @slug)

    # HTTP Last-Modified / ETag helps Google determine freshness and enables 304 responses
    fresh_when(last_modified: @file_mtime, public: true)
  end

  private

  def set_public_cache_headers
    response.headers["Cache-Control"] = "public, max-age=3600, s-maxage=86400, stale-while-revalidate=86400"
  end

  def doc_file_path(category, slug)
    path = CONTENT_PATH.join(category, "#{slug}.md")
    path if File.exist?(path)
  end

  def category_pages(category)
    dir = CONTENT_PATH.join(category)
    return [] unless Dir.exist?(dir)

    Dir.glob(dir.join("*.md")).filter_map do |file|
      slug = File.basename(file, ".md")
      next if slug.start_with?("_") # Skip index files

      content = File.read(file)
      frontmatter, = parse_frontmatter(content)

      {
        slug: slug,
        title: frontmatter["title"] || slug.titleize,
        description: frontmatter["description"],
        order: frontmatter["order"] || 999
      }
    end.sort_by { |p| p[:order] }
  end

  def parse_frontmatter(content)
    if content.start_with?("---")
      parts = content.split("---", 3)
      if parts.length >= 3
        frontmatter = YAML.safe_load(parts[1], permitted_classes: [ Date, Time ]) || {}
        return [ frontmatter, parts[2].strip ]
      end
    end
    [ {}, content ]
  end

  def render_markdown(content)
    renderer = RougeRenderer.new(with_toc_data: true, hard_wrap: true)
    markdown = Redcarpet::Markdown.new(renderer, {
      autolink: true,
      fenced_code_blocks: true,
      tables: true,
      strikethrough: true,
      no_intra_emphasis: true,
      highlight: true,
      footnotes: true,
      space_after_headers: true
    })
    markdown.render(content).html_safe
  end

  def generate_toc(content)
    headings = []
    content.scan(/^(\#{2,4})\s+(.+)$/) do |level, text|
      headings << {
        level: level.length,
        text: text.strip,
        id: text.strip.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
      }
    end
    headings
  end

  def find_adjacent_pages(current_slug)
    slugs = @pages.map { |p| p[:slug] }
    current_index = slugs.index(current_slug)
    return [ nil, nil ] unless current_index

    prev_page = current_index.positive? ? @pages[current_index - 1] : nil
    next_page = current_index < @pages.length - 1 ? @pages[current_index + 1] : nil
    [ prev_page, next_page ]
  end

  # Find pages from other categories that might be related (cross-linking helps SEO)
  def find_related_pages(current_category, current_slug)
    related = []
    CATEGORIES.each do |cat_slug, cat|
      next if cat_slug == current_category

      pages = category_pages(cat_slug)
      pages.each do |page|
        related << page.merge(category_slug: cat_slug, category_title: cat[:title])
      end
    end
    # Return up to 3 related pages, preferring guides and quickstart
    related.sort_by { |p| %w[guides quickstart].include?(p[:category_slug]) ? 0 : 1 }.first(3)
  end

  def render_not_found
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end

  # Custom Redcarpet renderer with Rouge syntax highlighting
  class RougeRenderer < Redcarpet::Render::HTML
    include Rouge::Plugins::Redcarpet

    def header(text, level)
      id = text.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
      %(<h#{level} id="#{id}" class="scroll-mt-24">#{text}</h#{level}>)
    end

    def block_code(code, language)
      lexer = Rouge::Lexer.find_fancy(language, code) || Rouge::Lexers::PlainText
      formatter = Rouge::Formatters::HTML.new
      highlighted = formatter.format(lexer.lex(code))

      <<~HTML
        <div class="code-block relative group my-4">
          <div class="code-copy-btn">
            <button type="button" class="btn btn-xs btn-ghost" data-controller="clipboard" data-action="click->clipboard#copy" data-clipboard-content-value="#{CGI.escapeHTML(code)}">
              <i class="fa-regular fa-copy"></i>
            </button>
          </div>
          #{%(<div class="text-xs text-base-content/50 px-4 pt-2">#{language}</div>) if language.present?}
          <pre class="highlight"><code class="language-#{language}">#{highlighted}</code></pre>
        </div>
      HTML
    end

    def table(header, body)
      %(<div class="overflow-x-auto my-4"><table class="table table-zebra">#{header}#{body}</table></div>)
    end

    def paragraph(text)
      # Handle callout blocks: > **Note:** or > **Warning:** etc.
      if text.start_with?("<strong>Note:</strong>", "<strong>Info:</strong>")
        return %(<div class="alert alert-info my-4 gap-4"><i class="fa-solid fa-circle-info shrink-0 text-lg"></i><span class="flex-1">#{text.sub(/^<strong>\w+:<\/strong>\s*/, "")}</span></div>)
      elsif text.start_with?("<strong>Warning:</strong>", "<strong>Caution:</strong>")
        return %(<div class="alert alert-warning my-4 gap-4"><i class="fa-solid fa-triangle-exclamation shrink-0 text-lg"></i><span class="flex-1">#{text.sub(/^<strong>\w+:<\/strong>\s*/, "")}</span></div>)
      elsif text.start_with?("<strong>Tip:</strong>")
        return %(<div class="alert alert-success my-4 gap-4"><i class="fa-solid fa-lightbulb shrink-0 text-lg"></i><span class="flex-1">#{text.sub(/^<strong>\w+:<\/strong>\s*/, "")}</span></div>)
      end

      %(<p class="my-3 leading-relaxed">#{text}</p>)
    end

    def list(contents, list_type)
      tag = list_type == :ordered ? "ol" : "ul"
      %(<#{tag} class="list-inside #{list_type == :ordered ? 'list-decimal' : 'list-disc'} my-4 space-y-2">#{contents}</#{tag}>)
    end

    def link(link, title, content)
      title_attr = title ? %( title="#{title}") : ""
      external = link.start_with?("http")
      target = external ? ' target="_blank" rel="noopener"' : ""
      %(<a href="#{link}"#{title_attr}#{target} class="link link-primary">#{content}</a>)
    end

    def codespan(code)
      %(<code class="px-1.5 py-0.5 bg-base-200 rounded text-sm font-mono">#{code}</code>)
    end
  end
end
