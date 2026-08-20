require "rails_helper"
require "rack/cors"

# L-21: the CORS initializer must FAIL CLOSED in production -- when
# CORS_ALLOWED_ORIGINS is unset (or blank) in production it must deny all
# cross-origin requests rather than falling back to the wildcard "*".
#
# The initializer registers Rack::Cors as application middleware at boot, so
# we can't easily mutate the already-built middleware stack. Instead we load
# the initializer file's `allow do ... end` block into a throwaway Rack::Cors
# instance (capturing it via a stub `insert_before`) under controlled
# Rails.env / ENV, then drive a real CORS preflight through it and inspect
# the Access-Control-Allow-Origin response header.
RSpec.describe "CORS initializer fail-closed (L-21)", type: :request do
  CORS_INITIALIZER = Rails.root.join("config/initializers/cors.rb").freeze

  # Builds a standalone Rack::Cors app configured by running the real
  # initializer file under the given Rails.env / CORS_ALLOWED_ORIGINS.
  def build_cors_app(rails_env:, allowed_origins:)
    captured_block = nil

    fake_middleware = Object.new
    fake_middleware.define_singleton_method(:insert_before) do |*_args, &block|
      captured_block = block
    end
    fake_config = Object.new
    fake_config.define_singleton_method(:middleware) { fake_middleware }
    fake_app = Object.new
    fake_app.define_singleton_method(:config) { fake_config }

    env_inquiry = ActiveSupport::StringInquirer.new(rails_env)

    allow(Rails).to receive(:application).and_return(fake_app)
    allow(Rails).to receive(:env).and_return(env_inquiry)

    original = ENV["CORS_ALLOWED_ORIGINS"]
    if allowed_origins.nil?
      ENV.delete("CORS_ALLOWED_ORIGINS")
    else
      ENV["CORS_ALLOWED_ORIGINS"] = allowed_origins
    end

    load CORS_INITIALIZER.to_s

    inner = ->(_env) { [ 200, { "Content-Type" => "text/plain" }, [ "ok" ] ] }
    Rack::Cors.new(inner, &captured_block)
  ensure
    if original.nil?
      ENV.delete("CORS_ALLOWED_ORIGINS")
    else
      ENV["CORS_ALLOWED_ORIGINS"] = original
    end
  end

  # Sends a CORS preflight (OPTIONS) for /api/* from `origin` and returns the
  # Access-Control-Allow-Origin response header (nil when CORS denied it).
  def preflight_allow_origin(app, origin:)
    env = Rack::MockRequest.env_for(
      "/api/v1/anything",
      method: "OPTIONS",
      "HTTP_ORIGIN" => origin,
      "HTTP_ACCESS_CONTROL_REQUEST_METHOD" => "GET"
    )
    status, headers, _body = app.call(env)
    headers["Access-Control-Allow-Origin"] || headers["access-control-allow-origin"]
  end

  it "DENIES all cross-origin requests in production when CORS_ALLOWED_ORIGINS is unset" do
    app = build_cors_app(rails_env: "production", allowed_origins: nil)
    expect(preflight_allow_origin(app, origin: "https://evil.example.com")).to be_nil
  end

  it "DENIES in production when CORS_ALLOWED_ORIGINS is blank" do
    app = build_cors_app(rails_env: "production", allowed_origins: "   ")
    expect(preflight_allow_origin(app, origin: "https://evil.example.com")).to be_nil
  end

  it "ALLOWS only the configured origins in production when CORS_ALLOWED_ORIGINS is set" do
    app = build_cors_app(rails_env: "production", allowed_origins: "https://app.mysigner.com")
    expect(preflight_allow_origin(app, origin: "https://app.mysigner.com")).to eq("https://app.mysigner.com")
    expect(preflight_allow_origin(app, origin: "https://evil.example.com")).to be_nil
  end

  it "keeps the permissive wildcard in development for convenience" do
    app = build_cors_app(rails_env: "development", allowed_origins: nil)
    expect(preflight_allow_origin(app, origin: "https://anything.example.com")).to eq("*")
  end
end
