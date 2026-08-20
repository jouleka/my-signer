# frozen_string_literal: true

namespace :seo do
  desc "Notify IndexNow (Bing/Yandex) about all public URLs for faster indexing"
  task notify_index_now: :environment do
    paths = []

    # Homepage
    paths << "/"

    # Docs index
    paths << "/docs"

    # Pricing
    paths << "/pricing"

    # All doc categories and pages
    DocsController::CATEGORIES.each do |slug, _category|
      paths << "/docs/#{slug}"

      dir = Rails.root.join("app/views/docs/content", slug)
      next unless Dir.exist?(dir)

      Dir.glob(dir.join("*.md")).each do |file|
        page_slug = File.basename(file, ".md")
        next if page_slug.start_with?("_")
        paths << "/docs/#{slug}/#{page_slug}"
      end
    end

    puts "Notifying IndexNow about #{paths.size} URLs..."
    paths.each { |p| puts "  #{p}" }

    IndexNowController.notify(paths)
    puts "Done! Search engines have been pinged."
  end
end
