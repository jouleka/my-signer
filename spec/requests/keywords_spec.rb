require "rails_helper"

RSpec.describe "Keywords", type: :request do
  let(:user) { create(:user, :pro_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) { create(:apple_app, organization: organization) }
  let(:keyword_id) { "apple_app_#{apple_app.id}" }

  before do
    sign_in user, scope: :user
  end

  describe "GET /organizations/:organization_id/keywords" do
    it "loads the keywords index" do
      get organization_keywords_path(organization)
      expect(response).to have_http_status(:ok)
    end

    it "redirects unauthenticated users" do
      sign_out user
      get organization_keywords_path(organization)
      expect(response).to redirect_to(new_user_session_path)
    end

    context "with free plan" do
      let(:user) { create(:user, plan_tier: :free) }

      it "shows read-only banner" do
        get organization_keywords_path(organization)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("keyword data is read-only")
      end
    end

    context "with pro plan and iOS apps" do
      let!(:listing) { create(:store_listing, :ios, organization: organization, listable: apple_app) }

      it "shows the app card" do
        get organization_keywords_path(organization)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(apple_app.name)
      end
    end
  end

  describe "GET /organizations/:organization_id/keywords/:id" do
    let!(:listing) { create(:store_listing, :ios, organization: organization, listable: apple_app, locale: "en-US") }

    it "loads the keyword dashboard" do
      get organization_keyword_path(organization, keyword_id)
      expect(response).to have_http_status(:ok)
    end

    it "defaults to editor tab" do
      get organization_keyword_path(organization, keyword_id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Editor")
    end

    it "loads the suggestions tab" do
      get organization_keyword_path(organization, keyword_id, tab: "suggestions")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Keyword Suggestions")
    end

    it "loads the tracking tab" do
      get organization_keyword_path(organization, keyword_id, tab: "tracking")
      expect(response).to have_http_status(:ok)
      # The Tracking tab card header says "Tracking"; the header icon is a
      # chart-line and the CTA is "Add keyword". Assert the CTA — it's
      # unique to this tab and survives a card-title rename.
      expect(response.body).to include("Add keyword")
    end

    context "with paused TKCs from a plan downgrade" do
      let!(:active_tk) { create(:tracked_keyword, apple_app: apple_app, keyword: "active-kw") }
      let!(:active_tkc) { create(:tracked_keyword_country, tracked_keyword: active_tk, country: "us") }
      let!(:paused_tk) { create(:tracked_keyword, apple_app: apple_app, keyword: "paused-kw") }
      let!(:paused_tkc) {
        create(:tracked_keyword_country, tracked_keyword: paused_tk, country: "us", enabled: false)
      }

      it "surfaces paused cards and the banner upgrade CTA on the tracking tab" do
        get organization_keyword_path(organization, keyword_id, tab: "tracking")
        expect(response).to have_http_status(:ok)

        # Banner shows the paused count and the upgrade affordance.
        expect(response.body).to include("1 paused")
        expect(response.body).to include("Upgrade to resume")

        # Fully-paused keyword card carries the "Paused — upgrade to resume"
        # annotation next to the keyword name.
        expect(response.body).to include("paused-kw")
        expect(response.body).to match(/Paused.*upgrade to resume/i)
      end
    end

    it "loads the locale map tab" do
      get organization_keyword_path(organization, keyword_id, tab: "locale_map")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Locale Keyword Map")
    end

    it "returns 404 for an unknown app id" do
      get organization_keyword_path(organization, "apple_app_99999999")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /organizations/:organization_id/keywords/suggestions" do
    it "returns JSON suggestions" do
      suggestions_service = instance_double(Aso::KeywordSuggestions, fetch: [ "productivity", "tools" ])
      allow(Aso::KeywordSuggestions).to receive(:new).and_return(suggestions_service)

      get suggestions_organization_keywords_path(organization, term: "product"), as: :json
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["suggestions"]).to eq([ "productivity", "tools" ])
    end

    it "returns empty array for blank term" do
      get suggestions_organization_keywords_path(organization, term: ""), as: :json
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["suggestions"]).to eq([])
    end
  end

  describe "GET /organizations/:id/keywords/suggestions — normalization" do
    let(:org)      { create(:organization) }
    let(:user)     { org.owner }

    before do
      user.update!(plan_tier: :pro)
      org.reset_entitlements_memo! if org.respond_to?(:reset_entitlements_memo!)
      sign_in user
    end

    it "normalizes Apple's autocomplete strings via Aso::KeywordNormalizer" do
      allow_any_instance_of(Aso::KeywordSuggestions).to receive(:fetch)
        .and_return([ "  Focus   Timer  ", "Café", "pomodoro" ])
      get suggestions_organization_keywords_path(org), params: { term: "foo" }
      json = JSON.parse(response.body)
      expect(json["suggestions"]).to eq([ "focus timer", "café", "pomodoro" ])
    end
  end

  # PATCH /organizations/:organization_id/keywords/:id removed. Tracking-add/remove
  # moved to TrackedKeywordsController (see spec/requests/tracked_keywords_spec.rb).

  describe "PATCH /organizations/:id/keywords/:id/append" do
    # Do NOT name this `let(:app)` — `app` in request specs is Rails.application,
    # and shadowing it breaks the URL-helper lookup (routes come off
    # `app.routes.url_helpers`). Use `ios_app` instead.
    let(:org)     { create(:organization) }
    let(:user)    { org.owner }
    let(:ios_app) { create(:apple_app, organization: org) }
    let!(:listing) { create(:store_listing, listable: ios_app, organization: org, locale: "en-US", keywords: "signer, codesigning") }

    before do
      user.update!(plan_tier: :pro)
      org.reset_entitlements_memo! if org.respond_to?(:reset_entitlements_memo!)
      sign_in user
    end

    let(:valid_params) do
      {
        keywords: %w[focus pomodoro],
        locale: "en-US",
        store_listing_updated_at: listing.updated_at.iso8601(6)
      }
    end

    it "appends normalized, deduped keywords to the listing" do
      patch append_organization_keyword_path(org, "apple_app_#{ios_app.id}"),
            params: valid_params,
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      listing.reload
      expect(listing.keywords.split(",").map(&:strip)).to match_array(%w[signer codesigning focus pomodoro])
    end

    it "rejects when store_listing_updated_at is stale" do
      stale = valid_params.merge(store_listing_updated_at: 1.day.ago.iso8601(6))
      patch append_organization_keyword_path(org, "apple_app_#{ios_app.id}"),
            params: stale,
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include("updated by someone else")
      expect(listing.reload.keywords).to eq("signer, codesigning")
    end

    it "filters out blank and already-present keywords" do
      patch append_organization_keyword_path(org, "apple_app_#{ios_app.id}"),
            params: valid_params.merge(keywords: [ "signer", "", "  ", "focus" ]),
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
      listing.reload
      expect(listing.keywords.split(",").map(&:strip)).to match_array(%w[signer codesigning focus])
    end

    it "emits a store_listing_keywords_updated audit event" do
      expect {
        patch append_organization_keyword_path(org, "apple_app_#{ios_app.id}"),
              params: valid_params,
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.to change { AuditEvent.where(action: "store_listing_keywords_updated").count }.by(1)
    end

    it "is denied on Free tier" do
      user.update!(plan_tier: :free)
      org.reset_entitlements_memo! if org.respond_to?(:reset_entitlements_memo!)
      patch append_organization_keyword_path(org, "apple_app_#{ios_app.id}"),
            params: valid_params
      expect(response).to redirect_to(organization_keywords_path(org))
    end

    it "returns without modifying keywords when an overflow append would fail validation" do
      long = "x" * 85
      listing.update!(keywords: long)
      patch append_organization_keyword_path(org, "apple_app_#{ios_app.id}"),
            params: valid_params.merge(store_listing_updated_at: listing.updated_at.iso8601(6)),
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
      # Either a 422 or a 200 with a banner is acceptable; the key invariant is
      # the listing must not have changed.
      expect(listing.reload.keywords).to eq(long)
    end
  end

  describe "POST /organizations/:id/keywords/competitor_lookup" do
    let(:org)  { create(:organization) }
    let(:user) { org.owner }

    before do
      user.update!(plan_tier: :pro)
      org.reset_entitlements_memo! if org.respond_to?(:reset_entitlements_memo!)
      sign_in user
    end

    it "returns the parsed competitor payload" do
      allow_any_instance_of(Aso::CompetitorLookup).to receive(:fetch).and_return(
        { track_name: "Bear", primary_genre: "Productivity", seller_name: "X", seed_terms: %w[bear notes] }
      )
      post competitor_lookup_organization_keywords_path(org),
           params: { app_id: 1016366447, country: "us" },
           headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["track_name"]).to eq("Bear")
      expect(json["seed_terms"]).to include("bear")
    end

    it "returns 422 for a bogus app_id" do
      post competitor_lookup_organization_keywords_path(org),
           params: { app_id: "xx", country: "us" },
           headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "is denied on Free tier" do
      user.update!(plan_tier: :free)
      org.reset_entitlements_memo! if org.respond_to?(:reset_entitlements_memo!)
      post competitor_lookup_organization_keywords_path(org),
           params: { app_id: 1, country: "us" },
           headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
    end
  end

  describe "competitor_lookup throttle", type: :request do
    # Rack::Attack captures Rails.cache (NullStore in test env) at boot time,
    # so request-level throttles are no-ops in the suite. Follow the established
    # project pattern from spec/requests/saml_metadata_controller_spec.rb:
    # assert the throttle is REGISTERED and its discriminator matches the
    # competitor_lookup path rather than trying to fire 10+ requests.
    # See PRODUCT_PIVOT_PLAN.md "Rack::Attack rate-limit automated specs —
    # middleware bypass in test env".
    it "registers a user-based throttle for competitor_lookup" do
      throttle = Rack::Attack.throttles["competitor_lookup/user"]
      expect(throttle).to be_present
      expect(throttle.limit).to eq(10)
      expect(throttle.period).to eq(1.minute)
    end

    it "registers an IP-based throttle for competitor_lookup" do
      throttle = Rack::Attack.throttles["competitor_lookup/ip"]
      expect(throttle).to be_present
      expect(throttle.limit).to eq(20)
      expect(throttle.period).to eq(1.minute)
    end

    it "matches the competitor_lookup path with the configured throttles" do
      org = create(:organization)
      path = competitor_lookup_organization_keywords_path(org)
      env  = Rack::MockRequest.env_for(path, method: "POST", "REMOTE_ADDR" => "1.2.3.4")
      req  = Rack::Attack::Request.new(env)

      ip_throttle = Rack::Attack.throttles["competitor_lookup/ip"]
      expect(ip_throttle.block.call(req)).to eq(req.ip)

      # The user throttle reads warden; when warden is absent (as in this bare
      # env) the block returns nil, which is the expected fail-closed behavior.
      user_throttle = Rack::Attack.throttles["competitor_lookup/user"]
      expect(user_throttle.block.call(req)).to be_nil
    end

    it "keys the user throttle on warden.user.id when a user is signed in" do
      org  = create(:organization)
      path = competitor_lookup_organization_keywords_path(org)
      env  = Rack::MockRequest.env_for(path, method: "POST")

      fake_user   = double("User", id: 42)
      fake_warden = double("Warden", user: fake_user)
      env["warden"] = fake_warden

      req = Rack::Attack::Request.new(env)
      user_throttle = Rack::Attack.throttles["competitor_lookup/user"]
      expect(user_throttle.block.call(req)).to eq(42)
    end

    it "does not match unrelated paths" do
      env = Rack::MockRequest.env_for("/up", method: "POST")
      req = Rack::Attack::Request.new(env)

      expect(Rack::Attack.throttles["competitor_lookup/ip"].block.call(req)).to be_nil
      expect(Rack::Attack.throttles["competitor_lookup/user"].block.call(req)).to be_nil
    end
  end
end
