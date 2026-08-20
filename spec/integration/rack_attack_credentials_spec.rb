require "rails_helper"

RSpec.describe "Rack::Attack credential throttle", type: :request do
  let(:user) { User.create!(email: "rack-attack-creds@example.com", password: "SecurePassword123!", confirmed_at: Time.current) }
  let(:org) { Organization.create!(name: "Rack Attack Test Org", owner: user) }
  let(:token_pair) { ApiToken.generate_for(user: user, organization: org, name: "Creds Throttle Token", scopes: %w[read write admin]) }
  let(:token_record) { token_pair[0] }
  let(:plain_token) { token_pair[1] }

  before do
    # Ensure Rack::Attack is enabled (test env may have it disabled elsewhere)
    Rack::Attack.enabled = true
    # Remember the original cache store so after: can restore it — test env
    # sets `config.cache_store = :null_store` so counters never accumulate
    # across tests; if we leave a real MemoryStore in place after this spec
    # runs, OTHER specs start hitting 429s on shared IP/global throttles.
    @original_rack_attack_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rails.application.env_config["action_dispatch.show_exceptions"] = :rescuable
    # Materialize the token
    token_record
  end

  after do
    Rack::Attack.cache.store.clear if Rack::Attack.cache.store.respond_to?(:clear)
    Rack::Attack.cache.store = @original_rack_attack_store if @original_rack_attack_store
  end

  it "throttles credential-read paths after 30 hits in a minute per token" do
    # Pin time inside a single 1-minute Rack::Attack bucket. Without this,
    # CI was flaky: 30 sequential HTTP requests can straddle the minute
    # boundary if CI is slow, the counter resets for the new bucket, and
    # the 31st request returns 200 instead of 429. travel_to stubs
    # Time.now (which Rack::Attack uses internally for bucket computation),
    # so all 31 requests fall in the same bucket deterministically.
    travel_to Time.zone.local(2026, 1, 1, 12, 0, 30) do
      30.times do
        get "/api/v1/organizations/#{org.id}/android_keystores", headers: auth_headers(plain_token)
      end
      get "/api/v1/organizations/#{org.id}/android_keystores", headers: auth_headers(plain_token)

      expect(response.status).to eq(429)
      expect(response.body).to include("rate_limit_exceeded")
    end
  end

  def auth_headers(tok)
    { "Authorization" => "Bearer #{tok}", "X-User-Email" => user.email }
  end
end
