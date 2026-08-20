require "rails_helper"

# Defends the per-token throttle on POST /account/restore. Devise's
# :lockable counter does NOT increment in this code path because the
# controller does a direct `valid_password?` bcrypt compare, bypassing
# the Warden strategy chain. The IP throttle is bypassable from a
# distributed attacker; the per-token throttle is the actual gate
# against any single hijacked link.
#
# Acceptable non-throttled response statuses for the pre-throttle
# attempts (wrong password against an existing token):
#   * 422 — controller renders :show with the "Incorrect password" alert
#   * 200 — same render path on a different Rails version / serializer
#   * 302 — flash-and-redirect variant if the controller is changed
# Anything else (500, 429, etc.) means a regression in either the
# controller path OR the throttle key.
ACCEPTABLE_PRE_THROTTLE_STATUSES = [ 200, 302, 422 ].freeze

RSpec.describe "Rack::Attack POST /account/restore per-token throttle", type: :request do
  let!(:user) do
    User.create!(
      email: "restore-throttle-#{SecureRandom.hex(4)}@example.test",
      password: "OriginalPassword123!",
      confirmed_at: Time.current
    )
  end
  let!(:plain_token) { user.soft_delete! }

  before do
    @original_rack_attack_enabled = Rack::Attack.enabled
    Rack::Attack.enabled = true
    @original_rack_attack_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rails.application.env_config["action_dispatch.show_exceptions"] = :rescuable
  end

  after do
    Rack::Attack.cache.store.clear if Rack::Attack.cache.store.respond_to?(:clear)
    Rack::Attack.cache.store = @original_rack_attack_store if @original_rack_attack_store
    # Restore Rack::Attack.enabled so other specs that rely on the
    # default test-env value aren't perturbed by this one.
    Rack::Attack.enabled = @original_rack_attack_enabled
  end

  it "throttles the 6th POST with the same token within 15 minutes (limit: 5)" do
    5.times do
      post "/account/restore", params: { token: plain_token, current_password: "WrongGuess#{rand(1000)}!" }
      expect(response.status).to be_in(ACCEPTABLE_PRE_THROTTLE_STATUSES),
        "pre-throttle attempt landed on #{response.status} (expected one of #{ACCEPTABLE_PRE_THROTTLE_STATUSES.inspect}) — controller wiring regression?"
    end

    post "/account/restore", params: { token: plain_token, current_password: "WrongGuess999!" }
    expect(response.status).to eq(429), "the 6th attempt with the same token must be throttled"
  end

  it "does NOT throttle attempts against DIFFERENT tokens (key is per-token, not global)" do
    other_user = User.create!(
      email: "restore-throttle-other-#{SecureRandom.hex(4)}@example.test",
      password: "OriginalPassword123!",
      confirmed_at: Time.current
    )
    other_token = other_user.soft_delete!

    # Burn the limit on `plain_token`
    5.times do
      post "/account/restore", params: { token: plain_token, current_password: "WrongGuess#{rand(1000)}!" }
    end
    post "/account/restore", params: { token: plain_token, current_password: "WrongGuess999!" }
    expect(response.status).to eq(429)

    # Different token must NOT be throttled (different key)
    post "/account/restore", params: { token: other_token, current_password: "WrongGuess0!" }
    expect(response.status).to be_in(ACCEPTABLE_PRE_THROTTLE_STATUSES),
      "throttle must scope per-token-hash; got #{response.status} for a fresh token"
  end
end
