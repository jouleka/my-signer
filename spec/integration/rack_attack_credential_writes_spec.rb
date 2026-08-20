require "rails_helper"

# Covers the throttles added for audit findings L-2, L-3, L-5:
#   L-2: DELETE /api/v1/organizations/:id/credentials (bulk purge)
#   L-3: GET .../profiles/:id/download and .../certificates/:id/download
#        share the credential-read budget
#   L-5: POST /organizations/:id/api_tokens (web token minting)
#
# These assert ONLY that Rack::Attack returns 429 once the limit is
# exceeded — they do not depend on the underlying controller succeeding,
# since the throttle is middleware that fires before routing.
RSpec.describe "Rack::Attack credential-write throttles", type: :request do
  let(:user) { User.create!(email: "rack-attack-cred-writes@example.com", password: "SecurePassword123!", confirmed_at: Time.current) }
  let(:org) { Organization.create!(name: "Rack Attack Writes Org", owner: user) }
  let(:token_pair) { ApiToken.generate_for(user: user, organization: org, name: "Writes Throttle Token", scopes: %w[read write admin]) }
  let(:token_record) { token_pair[0] }
  let(:plain_token) { token_pair[1] }

  before do
    Rack::Attack.enabled = true
    @original_rack_attack_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rails.application.env_config["action_dispatch.show_exceptions"] = :rescuable
    token_record
  end

  after do
    Rack::Attack.cache.store.clear if Rack::Attack.cache.store.respond_to?(:clear)
    Rack::Attack.cache.store = @original_rack_attack_store if @original_rack_attack_store
  end

  def auth_headers(tok)
    { "Authorization" => "Bearer #{tok}", "X-User-Email" => user.email }
  end

  # L-2 — bulk credential-purge DELETE is clamped to 5/min per token.
  it "throttles DELETE /credentials (bulk purge) after 5 hits in a minute per token" do
    travel_to Time.zone.local(2026, 1, 1, 12, 0, 30) do
      5.times do
        delete "/api/v1/organizations/#{org.id}/credentials", headers: auth_headers(plain_token)
      end
      delete "/api/v1/organizations/#{org.id}/credentials", headers: auth_headers(plain_token)

      expect(response.status).to eq(429)
      expect(response.body).to include("rate_limit_exceeded")
    end
  end

  # L-3 — profile download falls under the 30/min credential-read budget.
  it "throttles GET profiles/:id/download under the credential-read budget" do
    travel_to Time.zone.local(2026, 1, 1, 12, 0, 30) do
      30.times do
        get "/api/v1/organizations/#{org.id}/profiles/1/download", headers: auth_headers(plain_token)
      end
      get "/api/v1/organizations/#{org.id}/profiles/1/download", headers: auth_headers(plain_token)

      expect(response.status).to eq(429)
      expect(response.body).to include("rate_limit_exceeded")
    end
  end

  # L-3 — certificate download falls under the 30/min credential-read budget.
  it "throttles GET certificates/:id/download under the credential-read budget" do
    travel_to Time.zone.local(2026, 1, 1, 12, 0, 30) do
      30.times do
        get "/api/v1/organizations/#{org.id}/certificates/1/download", headers: auth_headers(plain_token)
      end
      get "/api/v1/organizations/#{org.id}/certificates/1/download", headers: auth_headers(plain_token)

      expect(response.status).to eq(429)
      expect(response.body).to include("rate_limit_exceeded")
    end
  end

  # L-5 — web API-token minting is capped at 10/hour per IP. The throttle is
  # middleware, so it fires before auth/CSRF — no signed-in session needed to
  # observe the 429.
  it "throttles POST /organizations/:id/api_tokens after 10 hits in an hour per IP" do
    travel_to Time.zone.local(2026, 1, 1, 12, 0, 30) do
      10.times do
        post "/organizations/#{org.id}/api_tokens", params: { api_token: { name: "x" } }
      end
      post "/organizations/#{org.id}/api_tokens", params: { api_token: { name: "x" } }

      expect(response.status).to eq(429)
    end
  end
end
