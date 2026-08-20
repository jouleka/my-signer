source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.2"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use PostgreSQL as the database for Active Record
gem "pg", ">= 1.5"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ mswin jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

# S3-compatible cloud storage for ActiveStorage exports
gem "aws-sdk-s3", require: false

# KMS for envelope encryption of customer signing credentials (CredentialVault)
gem "aws-sdk-kms", require: false

# Zip archive generation for screenshot exports
gem "rubyzip", require: "zip"

# Enable CORS for API requests (Swagger UI, CLI, etc.)
gem "rack-cors"


group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri mswin ], require: "debug/prelude"

  # Testing framework
  gem "rspec-rails"

  # Environment variables for local/dev/testing
  gem "dotenv-rails"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false
  gem "bundler-audit", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
  gem "factory_bot_rails"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Email preview in browser
  gem "letter_opener_web"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
  gem "webmock"
end

# Authentication
gem "devise"

# Background jobs (development uses Sidekiq; production currently uses Solid Queue)
gem "sidekiq"
gem "connection_pool", "< 3" # pin until sidekiq/rails fully support 3.x

# Rate limiting
gem "rack-attack"

# Authentication
gem "omniauth", ">= 2.1"
gem "omniauth-rails_csrf_protection"
gem "omniauth-google-oauth2"
gem "omniauth-github"
gem "omniauth-apple", github: "bvogel/omniauth-apple", branch: "fix/apple-session-handling"
# SAML 2.0 SSO for Team-tier orgs. Pin >= 1.18.1 to cover CVE-2024-45409
# (signature wrapping) AND CVE-2025-25291/25292/25293 + CVE-2025-54572
# (SAML auth bypass class). Audit this floor on every ruby-saml update.
gem "ruby-saml", ">= 1.18.1"
gem "omniauth-saml", "~> 2.1"

gem "tailwindcss-rails", "~> 4.3"

# Authorization
gem "pundit"

# HTTP + JWT (for App Store Connect client)
gem "jwt", ">= 2.7"
gem "faraday", ">= 2.9"
gem "faraday-retry", ">= 2.2"
# Persistent HTTP connections for App Store Connect (keep-alive across the
# ~100+ sequential API calls a sync makes, removes per-call TLS handshakes).
gem "faraday-net_http_persistent", ">= 2.3"
gem "net-http-persistent", ">= 4.0"

# Google Play Android Publisher API
gem "googleauth", ">= 1.11"
gem "google-apis-androidpublisher_v3", ">= 0.54.0"
gem "google-apis-playdeveloperreporting_v1beta1"

# OpenAI API for AI-powered store listing translations
gem "ruby-openai", "~> 8.3"

gem "kaminari", "~> 1.2"

# Markdown rendering for documentation
gem "redcarpet", "~> 3.6"
gem "rouge", "~> 4.2"

gem "dockerfile-rails", ">= 1.7", group: :development

gem "redis", "~> 5.4"

# Ruby 3.4+ stdlib gems that are no longer default
gem "csv"
