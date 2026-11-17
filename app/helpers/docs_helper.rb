# frozen_string_literal: true

module DocsHelper
  # Appended to short frontmatter descriptions so every docs page gets a
  # meta description long enough to be useful in search results.
  DOCS_DESCRIPTION_SUFFIXES = {
    "commands" => "MySigner CLI reference for building, signing and shipping iOS and Android apps.",
    "dashboard" => "MySigner web dashboard documentation for iOS and Android releases.",
    "guides" => "Step-by-step MySigner guide for shipping iOS and Android apps.",
    "quickstart" => "Install the MySigner CLI and ship iOS and Android apps from your terminal."
  }.freeze
  DOCS_DESCRIPTION_MIN_LENGTH = 90

  # Page <title> (before the " | MySigner" suffix). Articles and comparisons
  # already have long, descriptive titles, so the category is omitted there.
  def docs_page_title(title, category_slug, category)
    return title if %w[blog compare].include?(category_slug)

    if category_slug == "commands"
      # Command pages are titled with the bare command name ("upload").
      return "mysigner #{title} Command — CLI Reference" if title.match?(/\A[a-z][a-z-]*\z/)

      return "#{title} — CLI Reference"
    end

    "#{title} — #{category[:title]}"
  end

  def docs_meta_description(frontmatter, title, category_slug, category)
    description = frontmatter["description"].to_s.strip
    if description.blank?
      return "#{title} — MySigner #{category[:title].downcase} documentation for iOS and Android app signing."
    end

    suffix = DOCS_DESCRIPTION_SUFFIXES[category_slug]
    return description if suffix.nil? || description.length >= DOCS_DESCRIPTION_MIN_LENGTH

    "#{description.delete_suffix('.')}. #{suffix}"
  end
  def docs_breadcrumbs(category, page_title = nil)
    items = [
      { label: "Documentation", path: docs_path }
    ]

    if category
      items << { label: category[:title], path: category_docs_path(params[:category]) }
    end

    if page_title
      items << { label: page_title }
    end

    items
  end

  def toc_level_class(level)
    case level
    when 2 then ""
    when 3 then "ml-4"
    when 4 then "ml-8"
    else ""
    end
  end

  def doc_categories
    DocsController::CATEGORIES
  end

  def category_icon_bg(category_slug)
    case category_slug
    when "quickstart" then "bg-primary/10 text-primary"
    when "commands" then "bg-secondary/10 text-secondary"
    when "guides" then "bg-accent/10 text-accent"
    when "dashboard" then "bg-info/10 text-info"
    else "bg-base-200 text-base-content"
    end
  end

  # Returns all documentation pages for search functionality
  def all_docs_pages_for_search
    categories = DocsController::CATEGORIES
    content_path = Rails.root.join("app/views/docs/content")

    categories.flat_map do |slug, category|
      dir = content_path.join(slug)
      next [] unless Dir.exist?(dir)

      Dir.glob(dir.join("*.md")).filter_map do |file|
        page_slug = File.basename(file, ".md")
        next if page_slug.start_with?("_")

        content = File.read(file)
        frontmatter = parse_frontmatter_for_search(content)

        {
          title: frontmatter["title"] || page_slug.titleize,
          description: frontmatter["description"],
          category: slug,
          categoryTitle: category[:title],
          icon: category[:icon],
          path: page_docs_path(slug, page_slug)
        }
      end
    end.compact
  end

  private

  def parse_frontmatter_for_search(content)
    return {} unless content.start_with?("---")

    parts = content.split("---", 3)
    return {} unless parts.length >= 3

    YAML.safe_load(parts[1], permitted_classes: [ Date, Time ]) || {}
  rescue StandardError
    {}
  end
end
