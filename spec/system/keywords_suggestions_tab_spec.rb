require "rails_helper"

RSpec.describe "Keywords Suggestions tab", type: :system, js: true do
  let(:org)     { create(:organization) }
  let(:user)    { org.owner }
  let(:app)     { create(:apple_app, organization: org) }
  let!(:listing) { create(:store_listing, listable: app, locale: "en-US", keywords: "") }

  before do
    # Use the same plan-tier pattern as spec/policies/tracked_keyword_policy_spec.rb:
    # Organization#plan_tier delegates to owner.plan_tier; use :pro_plan trait or update owner.
    user.update!(plan_tier: :pro) if user.respond_to?(:plan_tier=)
    org.reset_entitlements_memo! if org.respond_to?(:reset_entitlements_memo!)

    sign_in user
    allow_any_instance_of(Aso::KeywordSuggestions).to receive(:fetch)
      .and_return(%w[focus timer pomodoro])
  end

  # We target chips via `span[data-keyword][data-state]` rather than just
  # `[data-keyword='X']` because the chip's bookmark icon (a nested <i>) also
  # carries `data-keyword` — the `[data-state]` narrows the match to the chip
  # root span, which is what clicks should land on.
  it "stages and unstages chips without the stacked-ring bug" do
    visit organization_keyword_path(org, "apple_app_#{app.id}", tab: "suggestions")
    # Wait for the Stimulus controller to connect before we try to type.
    expect(page).to have_css("[data-controller~='keyword-editor']", wait: 5)
    input = find("[data-keyword-editor-target='suggestionsInput']")
    input.fill_in(with: "foc")
    # Selenium's fill_in doesn't always dispatch an `input` event to Stimulus
    # controllers, so trigger it explicitly to simulate real typing.
    page.execute_script(<<~JS)
      const el = document.querySelector('[data-keyword-editor-target="suggestionsInput"]');
      el.dispatchEvent(new Event("input", { bubbles: true }));
    JS
    expect(page).to have_css("span[data-keyword='focus'][data-state]", wait: 5)

    find("span[data-keyword='focus'][data-state]").click
    # The controller rerenders on each click; wait for the staged state to
    # settle before clicking the next chip (the refetch is debounced + async,
    # so back-to-back clicks can race on the chip DOM).
    expect(page).to have_css("span[data-keyword='focus'][data-state='staged']", wait: 3)
    find("span[data-keyword='timer'][data-state='available']").click
    expect(page).to have_css("span[data-keyword='timer'][data-state='staged']", wait: 3)

    staged = page.all("span[data-state='staged']").map { |el| el["data-keyword"] }
    expect(staged).to match_array(%w[focus timer])
    # Kills the "stacked ring" bug: the previous implementation added
    # `ring-2` on each click without clearing prior state, so repeat clicks
    # stacked rings in the DOM. The new basket-derived render leaves no
    # ring classes anywhere on the page.
    expect(page).to have_no_css(".ring-2")

    find("span[data-keyword='focus'][data-state='staged']").click
    expect(page).to have_css("span[data-keyword='focus'][data-state='available']", wait: 3)
    expect(page).to have_css("span[data-keyword='timer'][data-state='staged']")
  end

  it "renders popularity pips when Apple Ads data is present" do
    create(:apple_ads_recommendation, apple_app: app, keyword: "focus", search_popularity: 75)

    # Make the credential return last_successful? == true
    credential = instance_double("AppleAdsCredential", last_successful?: true)
    allow_any_instance_of(Organization).to receive(:apple_ads_credential).and_return(credential)

    visit organization_keyword_path(org, "apple_app_#{app.id}", tab: "suggestions")
    # Wait for Stimulus to connect before typing (same pattern as the spec above).
    expect(page).to have_css("[data-controller~='keyword-editor']", wait: 5)
    input = find("[data-keyword-editor-target='suggestionsInput']")
    input.fill_in(with: "foc")
    page.execute_script(<<~JS)
      const el = document.querySelector('[data-keyword-editor-target="suggestionsInput"]');
      el.dispatchEvent(new Event("input", { bubbles: true }));
    JS

    # The pip is an inline-flex wrapper with no text content, so some headless
    # drivers treat it as non-visible — match with visible: :all.
    within("span[data-keyword='focus'][data-state]", wait: 3) do
      expect(page).to have_css("[title*='Apple Ads popularity: 75']", visible: :all, wait: 3)
    end
  end

  it "bookmarks a suggestion to the scratchpad" do
    visit organization_keyword_path(org, "apple_app_#{app.id}", tab: "suggestions")
    fill_in placeholder: "Type a seed keyword, or try a competitor app name...", with: "foc"

    # Wait for chips to render (see sister spec for the Selenium/Stimulus quirk).
    page.find_field(placeholder: "Type a seed keyword, or try a competitor app name...")
        .evaluate_script("this.dispatchEvent(new Event('input', { bubbles: true }))")
    expect(page).to have_css("span[data-keyword='focus'][data-state]", wait: 3)

    # Click the bookmark icon inside the chip specifically.
    within("span[data-keyword='focus'][data-state]") do
      find(".fa-bookmark").click
    end

    # Turbo Stream should replace the scratchpad zone; assert by DB state + visible content.
    expect(page).to have_css("#scratchpad", text: "focus", wait: 3)
    expect(SavedKeywordIdea.where(apple_app: app, keyword: "focus").count).to eq(1)
  end

  it "stages an Apple Ads recommendation into the basket" do
    create(:apple_ads_recommendation, apple_app: app, keyword: "focus", search_popularity: 75)

    credential = instance_double("AppleAdsCredential", last_successful?: true)
    allow_any_instance_of(Organization).to receive(:apple_ads_credential).and_return(credential)

    visit organization_keyword_path(org, "apple_app_#{app.id}", tab: "suggestions")

    within("#apple-ads-recommendations", wait: 3) do
      click_button("+ Stage", match: :first)
    end

    expect(page).to have_css("[data-keyword-editor-target='basketZone']:not(.hidden)", wait: 3)
  end

  it "strikes through Apple Ads rows already present in listing keywords" do
    create(:apple_ads_recommendation, apple_app: app, keyword: "focus", search_popularity: 75)
    listing.update!(keywords: "focus")

    credential = instance_double("AppleAdsCredential", last_successful?: true)
    allow_any_instance_of(Organization).to receive(:apple_ads_credential).and_return(credential)

    visit organization_keyword_path(org, "apple_app_#{app.id}", tab: "suggestions")
    expect(page).to have_css("#apple-ads-recommendations .line-through", text: "focus", wait: 3)
  end

  it "stages, commits, and clears — budget bar reflects the write" do
    visit organization_keyword_path(org, "apple_app_#{app.id}", tab: "suggestions")
    fill_in placeholder: "Type a seed keyword, or try a competitor app name...", with: "foc"

    # Trigger Stimulus (Selenium/Chromium quirk).
    page.find_field(placeholder: "Type a seed keyword, or try a competitor app name...")
        .evaluate_script("this.dispatchEvent(new Event('input', { bubbles: true }))")

    expect(page).to have_css("span[data-keyword='focus'][data-state]", wait: 3)

    find("span[data-keyword='focus'][data-state]").click
    find("span[data-keyword='timer'][data-state]").click

    expect(page).to have_css("[data-keyword-editor-target='basketZone']:not(.hidden)", wait: 2)

    click_button("Review & commit →", match: :first)
    expect(page).to have_css("#commit-basket-modal[open]", wait: 3)

    # Wait for the commit-basket-preview controller's MutationObserver to fire
    # and populate one hidden input per staged keyword before submitting.
    expect(page).to have_css(
      "#commit-basket-modal input[name='keywords[]']",
      count: 2, visible: :all, wait: 3
    )

    within("#commit-basket-modal") { click_button "Save to listing" }

    # The append turbo stream prepends into #keywords-flash-zone. The modal
    # backdrop hides it from Capybara's default visibility filter, so scope
    # to the zone and permit invisible matches.
    expect(page).to have_css(
      "#keywords-flash-zone", text: "Added to listing", visible: :all, wait: 5
    )
    expect(listing.reload.keywords.split(",").map(&:strip)).to include("focus", "timer")

    # The `:ok` Turbo Stream dispatches a `keyword-editor:committed` CustomEvent
    # (via an inline nonce'd <script>) that the controller listens for on
    # `document`. Its handler clears `this.basket`, closes the dialog, and
    # refreshes `keywordsStrValue`. Verify both the basket hides and the
    # modal actually closes. The basket uses the `hidden` utility (display:none)
    # so Capybara's default visibility filter would skip it; pass `visible: :all`.
    expect(page).to have_css(
      "[data-keyword-editor-target='basketZone'].hidden",
      visible: :all, wait: 3
    )
    expect(page).to have_no_css("#commit-basket-modal[open]")
  end
end
