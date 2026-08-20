# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
# Uncomment the line below in case you have `--require rails_helper` in the `.rspec` file
# that will avoid rails generators crashing because migrations haven't been run yet
# return unless Rails.env.test?
require 'rspec/rails'
# Test helpers
require 'devise'
require 'sidekiq/testing'
Sidekiq::Testing.fake!
require 'warden/test/helpers'
# Add additional requires below this line. Rails is not loaded until this point!

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories. Files matching `spec/**/*_spec.rb` are
# run as spec files by default. This means that files in spec/support that end
# in _spec.rb will both be required and run as specs, causing the specs to be
# run twice. It is recommended that you do not name files matching this glob to
# end with _spec.rb. You can configure this pattern with the --pattern
# option on the command line or in ~/.rspec, .rspec or `.rspec-local`.
#
# The following line is provided for convenience purposes. It has the downside
# of increasing the boot-up time by auto-requiring all files in the support
# directory. Alternatively, in the individual `*_spec.rb` files, manually
# require only the support files necessary.
#
Rails.root.glob('spec/support/**/*.rb').sort_by(&:to_s).each { |f| require f }

# Ensures that the test database schema matches the current schema file.
# If there are pending migrations it will invoke `db:test:prepare` to
# recreate the test database by loading the schema.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end
RSpec.configure do |config|
  # Make travel / travel_to / freeze_time available in every example.
  config.include ActiveSupport::Testing::TimeHelpers

  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = [
    Rails.root.join('spec/fixtures')
  ]

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true
  config.include FactoryBot::Syntax::Methods
  # Devise helpers for request specs
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Warden::Test::Helpers, type: :request
  config.after(:each, type: :request) { Warden.test_reset! }

  # Ensure Sidekiq queues are clean between examples
  config.before(:each) { Sidekiq::Worker.clear_all }

  # Skip the 14-day reverse-trial auto-start by default in tests so specs can
  # exercise predictable plan_tier defaults (matches the DB-level default of
  # "free"). Tests that need to exercise the real signup-to-trial flow can
  # opt in with User.with_reverse_trial { ... } or by setting
  # User.skip_reverse_trial_on_create = false at the start of the example.
  config.before(:each) { User.skip_reverse_trial_on_create = true }

  # Skip the ToS acceptance validation by default in tests. The validation
  # exists to enforce GDPR-compliant consent on the public sign-up form;
  # the bulk of our specs create users via `User.create!`/factories without
  # going through that form, so they shouldn't need to set `accepts_terms`.
  # Specs that exercise the real consent flow (e.g. registrations request
  # specs) opt back in with User.with_terms_acceptance_validation { ... }
  # or by setting User.skip_terms_acceptance_validation = false.
  config.before(:each) { User.skip_terms_acceptance_validation = true }

  # You can uncomment this line to turn off ActiveRecord support entirely.
  # config.use_active_record = false

  # RSpec Rails uses metadata to mix in different behaviours to your tests,
  # for example enabling you to call `get` and `post` in request specs. e.g.:
  #
  #     RSpec.describe UsersController, type: :request do
  #       # ...
  #     end
  #
  # The different available types are documented in the features, such as in
  # https://rspec.info/features/8-0/rspec-rails
  #
  # You can also this infer these behaviours automatically by location, e.g.
  # /spec/models would pull in the same behaviour as `type: :model` but this
  # behaviour is considered legacy and will be removed in a future version.
  #
  # To enable this behaviour uncomment the line below.
  # config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")
end
