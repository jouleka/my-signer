require "rails_helper"

# System coverage for the Apple Ads recommendations block that lives at the
# bottom of the Suggestions tab (Task 18). Four render states:
# Free-tier upsell, Pro-no-credential CTA, empty-state, and populated list.
RSpec.describe "Apple Ads recommendations in Suggestions tab", type: :system, js: true do
  let(:user) { create(:user, :pro_plan) }
  let(:org)  { create(:organization, owner: user) }
  let!(:app) { create(:apple_app, organization: org) }

  before { sign_in user }

  context "Pro+ with no Apple Ads credential" do
    it "shows the 'Connect Apple Search Ads' CTA inside the recommendations card" do
      visit organization_keyword_path(org, "apple_app_#{app.id}", tab: "suggestions")
      expect(page).to have_content("Apple's recommendations for this app")
      # Scope to the recommendations card by its id; the Connect-copy also
      # appears at the top connection banner, so a generic selector like
      # `section` matches multiple chrome sections on the page.
      within("#apple-ads-recommendations") do
        expect(page).to have_content(/Connect Apple Search Ads/i)
      end
    end
  end

  context "Pro+ with a successful credential but no recommendations yet" do
    before do
      create(:apple_ads_credential, organization: org, last_successful_at: 1.hour.ago)
    end

    it "shows the empty-state hint" do
      visit organization_keyword_path(org, "apple_app_#{app.id}", tab: "suggestions")
      expect(page).to have_content(/No recommendations yet/i)
    end
  end

  context "Pro+ with populated recommendations" do
    before do
      create(:apple_ads_credential, organization: org, last_successful_at: 1.hour.ago)
      create(:apple_ads_recommendation,
             apple_app: app, keyword: "photo editor",
             search_popularity: 85, bid_amount_micros: 1_500_000)
      create(:apple_ads_recommendation,
             apple_app: app, keyword: "photo collage",
             search_popularity: 62, bid_amount_micros: 900_000)
    end

    it "lists recommendations with keyword text + bid amount" do
      visit organization_keyword_path(org, "apple_app_#{app.id}", tab: "suggestions")
      expect(page).to have_content("photo editor")
      expect(page).to have_content("photo collage")
      # Bid is formatted as "$1.50 bid" — 1_500_000 micros → $1.50.
      expect(page).to have_content(/\$1\.50/)
    end

    it "shows 'Tracked' for recommendations already in the tracked-keyword list" do
      create(:tracked_keyword, apple_app: app, keyword: "photo editor")
      visit organization_keyword_path(org, "apple_app_#{app.id}", tab: "suggestions")
      within("#apple-ads-recommendations") do
        expect(page).to have_content("photo editor", wait: 5)
        within("li", text: "photo editor") do
          expect(page).to have_content("Tracked")
          expect(page).not_to have_button("Track")
        end
      end
    end

    it "tracks a recommendation on click" do
      visit organization_keyword_path(org, "apple_app_#{app.id}", tab: "suggestions")

      # The Track button uses data: { turbo: false } so that on successful
      # create the server's HTML redirect carries the user to the Tracking
      # tab (otherwise a turbo_stream targeting DOM ids absent from the
      # Suggestions tab would be a silent no-op). With Turbo disabled the
      # form submits as a native browser POST; Turbo's setConfirmMethod
      within("#apple-ads-recommendations") do
        expect(page).to have_content("photo editor", wait: 5)
        within("li", text: "photo editor") do
          click_button "Track"
        end
      end

      # Wait for the native-form POST + HTML redirect to actually land on the
      # Tracking tab before asserting DB state. On some CI drivers click_button
      # returns before the navigation settles, so the DB check can race the
      # server commit. Use the redirected URL as the synchronization point.
      expect(page).to have_current_path(
        organization_keyword_path(org, "apple_app_#{app.id}", tab: "tracking"),
        wait: 10
      )

      expect(TrackedKeyword.where(apple_app: app, keyword: "photo editor")).to exist
      # Since turbo: false, the browser follows the redirect to the
      # Tracking tab where the new keyword appears — giving the user
      # visual confirmation instead of the silent no-op they saw before.
      expect(page).to have_content("photo editor")
    end
  end

  context "Free tier" do
    before do
      user.update!(plan_tier: :free)
      org.reload.reset_entitlements_memo!
    end

    it "shows the Pro upsell banner in the recommendations card" do
      visit organization_keyword_path(org, "apple_app_#{app.id}", tab: "suggestions")
      expect(page).to have_content("Apple's recommendations for this app")
      expect(page).to have_content(/Pro/i)
      expect(page).to have_link("See plans \u2192")
    end
  end
end
