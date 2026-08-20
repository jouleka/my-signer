# Minimal Capybara system-test config. We register a headless-Chrome
# driver backed by selenium-webdriver (>= 4.x ships Selenium Manager
# which handles chromedriver download automatically).
#
# System specs opt in by declaring `type: :system, js: true`; this block
# also wires in Devise / Warden helpers so `sign_in` works as expected
# across the Capybara app server boundary.

require "capybara/rspec"
require "selenium-webdriver"

Capybara.register_driver :headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--no-sandbox")
  options.add_argument("--disable-dev-shm-usage")
  options.add_argument("--disable-gpu")
  options.add_argument("--window-size=1400,900")
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.javascript_driver = :headless_chrome
Capybara.default_max_wait_time = 5
Capybara.server = :puma, { Silent: true }

# Other spec files load webmock/rspec, which globally disables net
# connections. Capybara's internal :identify:__ ping to the app server
# runs on localhost; allow local HTTP so system specs work regardless
# of file-load order in a full suite run.
begin
  require "webmock"
  WebMock.disable_net_connect!(allow_localhost: true) if defined?(WebMock)
rescue LoadError
  # webmock not loaded in this run — nothing to do.
end

RSpec.configure do |config|
  config.include Devise::Test::IntegrationHelpers, type: :system
  config.include Warden::Test::Helpers, type: :system
  # Mount Rails routes so specs can call organization_keyword_path etc.
  # directly without prefixing app.url_helpers.
  config.include Rails.application.routes.url_helpers, type: :system

  config.before(:each, type: :system) do |example|
    driven_by(example.metadata[:js] ? :headless_chrome : :rack_test)
  end

  config.after(:each, type: :system) { Warden.test_reset! }
end
