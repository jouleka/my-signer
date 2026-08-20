require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module MySigner
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Background job adapter for development.
    # `:async` runs jobs on a thread pool inside the Rails process — zero extra
    # process to manage, no Redis dependency, jobs always run when enqueued.
    # Production uses solid_queue (see config/environments/production.rb).
    # Dev mirrors production by default so jobs actually run in a separate
    # `bin/jobs` worker process. The previous `async` default ran jobs in
    # the Puma thread pool, which meant ANY long-running job (the
    # keyword-rank check is the canonical offender — it talks to Apple
    # Search Ads + Apple's popularity endpoint) got SIGTERM'd whenever
    # dev-mode reloaded the web server, leaving a stranded
    # `OrgSyncRun` row that the dashboard surfaced as
    # "Sync did not complete (worker exited before finishing)" with no
    # actual underlying job failure.
    #
    # Override with DEV_QUEUE_ADAPTER=async (run jobs in-process, fastest
    # boot, fragile) or DEV_QUEUE_ADAPTER=inline (run jobs synchronously
    # in the request thread — useful for stepping through with debug)
    # or DEV_QUEUE_ADAPTER=sidekiq if you keep a Sidekiq+Redis stack.
    #
    # Pair this with `bin/jobs` running in a second terminal (or the
    # `worker:` line in Procfile.dev).
    if Rails.env.development?
      config.active_job.queue_adapter = ENV.fetch("DEV_QUEUE_ADAPTER", "solid_queue").to_sym
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Rack::Attack for rate limiting
    config.middleware.use Rack::Attack
  end
end
