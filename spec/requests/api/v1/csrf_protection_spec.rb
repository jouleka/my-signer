require 'rails_helper'

# Covers mysigner security-audit finding L-4 (CSRF on session-cookie-authed
# state-changing API actions) and the related current_organization fallback
# scoping fix, both in Api::V1::ApplicationController.
RSpec.describe "API v1 CSRF protection", type: :request do
  let(:user) { User.create!(email: "owner@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :pro) }
  let(:org)  { Organization.create!(name: "Owner Org", owner: user) }

  let(:other_user) { User.create!(email: "stranger@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :pro) }
  let(:foreign_org) { Organization.create!(name: "Foreign Org", owner: other_user) }

  let(:write_token) do
    ApiToken.generate_for(user: user, organization: org, name: "Write Token", scopes: [ "read", "write" ]).last
  end

  # The test environment disables forgery protection globally
  # (config.action_controller.allow_forgery_protection = false), which would
  # short-circuit verified_request?. Flip it on just for the examples that
  # exercise the CSRF branch, and restore it afterward so the rest of the suite
  # is unaffected.
  def with_forgery_protection
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    Api::V1::ApplicationController.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = previous
    Api::V1::ApplicationController.allow_forgery_protection = previous
  end

  # Establish a real Rack session cookie via an actual sign-in rather than the
  # Devise test helper. The helper's Warden injection is order-dependent in
  # isolation (it relies on test-mode state a prior spec may have warmed), which
  # made the cookie-auth 403 path nondeterministic (401 in isolation). A real
  # login POST sets the warden.user session key deterministically. Forgery
  # protection is globally off here (toggled on only inside with_forgery_protection),
  # so this login itself needs no CSRF token.
  def establish_session!(account, password: "SecurePassword123!")
    post user_session_path, params: { user: { email: account.email, password: password } }
  end

  describe "state-changing action via session-cookie auth" do
    before { establish_session!(user) }

    it "rejects a cookie-authed POST that carries no CSRF token" do
      with_forgery_protection do
        post "/api/v1/organizations/#{org.id}/devices",
             params: { name: "Phone", udid: "abc123", platform: "IOS" }
      end

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("invalid_csrf_token")
    end

    it "does not CSRF-check GET requests for cookie auth" do
      with_forgery_protection do
        get "/api/v1/organizations/#{org.id}/devices"
      end

      # Whatever the outcome, it must NOT be the CSRF rejection.
      expect(response).not_to have_http_status(:forbidden) if response.body.present?
      json = response.body.present? ? JSON.parse(response.body) : {}
      expect(json["error"]).not_to eq("invalid_csrf_token")
    end
  end

  describe "state-changing action via API token auth" do
    it "skips CSRF for a token-authed POST (no CSRF token present)" do
      with_forgery_protection do
        post "/api/v1/organizations/#{org.id}/devices",
             params: { name: "Phone", udid: "abc123", platform: "IOS" },
             headers: { "Authorization" => "Bearer #{write_token}" }
      end

      # The request must pass the CSRF gate. It may fail downstream for an
      # unrelated reason (e.g. no active App Store Connect credential), but it
      # must NOT be rejected as a CSRF failure.
      json = response.body.present? ? JSON.parse(response.body) : {}
      expect(json["error"]).not_to eq("invalid_csrf_token")
    end
  end

  describe "#current_organization fallback scoping (session auth)" do
    # The fallback is a private helper on the base controller. Exercise it
    # directly so the assertion pins the scoping behaviour rather than relying
    # on a downstream controller's own Organization.find lookup.
    let(:controller) do
      Api::V1::ApplicationController.new.tap do |c|
        c.instance_variable_set(:@current_user, user)
        c.instance_variable_set(:@current_api_token, nil)
      end
    end

    def fallback_for(org_id)
      allow(controller).to receive(:params).and_return(
        ActionController::Parameters.new(organization_id: org_id)
      )
      controller.send(:current_organization)
    end

    it "cannot select a foreign organization the user does not belong to" do
      expect(fallback_for(foreign_org.id)).to be_nil
    end

    it "resolves the user's own organization" do
      expect(fallback_for(org.id)).to eq(org)
    end

    it "returns nil when no organization_id param is present" do
      expect(fallback_for(nil)).to be_nil
    end

    it "end-to-end: a foreign org's resources are never served to a session user" do
      establish_session!(user)
      get "/api/v1/organizations/#{foreign_org.id}/devices"

      expect(response).not_to have_http_status(:ok)
      expect(response).not_to have_http_status(:created)
    end
  end
end
