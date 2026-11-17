require "rails_helper"

RSpec.describe "Store listings", type: :system, js: true do
  include ActiveJob::TestHelper
  let(:user) { create(:user, :team_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:app) { create(:apple_app, organization: organization) }
  let!(:english) { create(:store_listing, :synced, organization: organization, listable: app, locale: "en-US") }
  let!(:german) { create(:store_listing, organization: organization, listable: app, locale: "de-DE") }

  before do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    user.update!(last_organization: organization)
    sign_in user
  end

  it "displays server validation errors, then saves a corrected draft" do
    visit listing_path
    fill_in "store_listing_app_name", with: "x" * 31
    click_button "Save", exact: true
    expect(page).to have_content("App name is too long")
    expect(english.reload.app_name).not_to eq("x" * 31)
    fill_in "store_listing_app_name", with: "Corrected name"
    click_button "Save", exact: true
    expect(page).to have_css('[data-store-listing-editor-target="savingIndicator"]', text: "Saved")
    page.refresh
    expect(page).to have_field("store_listing_app_name", with: "Corrected name")
  end

  it "counts Apple's keyword byte limit and persists a corrected value" do
    visit listing_path
    fill_in "store_listing_keywords", with: "界" * 34
    expect(page).to have_content(/102\s*\/100 bytes/)
    click_button "Save", exact: true
    expect(page).to have_content("maximum is 100 bytes, got 102")
    fill_in "store_listing_keywords", with: "検索,写真,編集"
    click_button "Save", exact: true
    expect(page).to have_css('[data-store-listing-editor-target="savingIndicator"]', text: "Saved")
    page.refresh
    expect(page).to have_field("store_listing_keywords", with: "検索,写真,編集")
    expect(english.reload.keywords).to eq("検索,写真,編集")
  end

  it "saves before translating, shows pending through reload, and displays a failed job with retry" do
    visit listing_path("de-DE")
    fill_in "store_listing_description", with: "Keep this German draft"
    click_button "AI Translate", exact: false
    expect(page).to have_css('#ai-translate-listing-button button[aria-busy="true"]')
    expect(german.reload.description).to eq("Keep this German draft")
    page.refresh
    expect(page).to have_css('#ai-translate-listing-button button[aria-busy="true"]')
    translator = instance_double(StoreListingSync::AiTranslator)
    allow(StoreListingSync::AiTranslator).to receive(:new).and_return(translator)
    allow(translator).to receive(:translate!).and_raise("Translation provider unavailable")
    expect { perform_enqueued_jobs(only: StoreListingTranslationJob) }.to raise_error("Translation provider unavailable")
    page.refresh
    expect(page).to have_content("Translation provider unavailable")
    expect(page).to have_field("store_listing_description", with: "Keep this German draft")
    expect(page).to have_button("AI Translate", disabled: false)
    allow(translator).to receive(:translate!) { german.update!(description: "Übersetzte Beschreibung", translation_status: "needs_review") }
    click_button "AI Translate", exact: false
    expect(page).to have_css('#ai-translate-listing-button button[aria-busy="true"]')
    perform_enqueued_jobs(only: StoreListingTranslationJob)
    page.refresh
    expect(page).to have_field("store_listing_description", with: "Übersetzte Beschreibung")
    expect(page).to have_css('[aria-label="AI-translated, needs review"]')
  end

  it "keeps a queued sync pending and shows failure with an enabled retry button" do
    visit listing_path
    page.execute_script(<<~JS)
      window.originalFetch = window.fetch;
      window.fetch = async (url, options) => {
        const response = await window.originalFetch(url, options);
        if (String(url).includes("sync_status")) document.body.dataset.polled = "true";
        return response;
      };
    JS
    click_button "Sync from Store", exact: false
    expect(page).to have_content("Syncing from store")
    expect(page).to have_css('body[data-polled="true"]', wait: 6)
    expect(page).to have_content("Syncing from store")
    progress = StoreListingSync::OperationStatus.new(app)
    progress.update(progress.read[:id], status: "failed", error: "Store unavailable")
    expect(page).to have_content("Sync failed", wait: 6)
    expect(page).to have_content("Store unavailable")
    expect(page).to have_button("Sync from Store", disabled: false)
    page.refresh
    expect(page).to have_content("Store unavailable")
  end

  it "waits for a secondary locale and keeps its push failure visible on the primary locale" do
    english.update!(push_status: "success")
    german.update!(push_status: "pushing")
    visit listing_path
    expect(page).to have_content("Pushing changes")
    german.update!(push_status: "failed", push_error: "German listing rejected")
    expect(page).to have_content("de-DE: German listing rejected", wait: 6)
    page.refresh
    expect(page).to have_content("de-DE: German listing rejected")
    expect(page).to have_button("Push to App Store", disabled: false)
  end

  it "saves before pushing, displays a failed batch, and allows retry" do
    english.update!(support_url: "https://example.test/support", privacy_policy_url: "https://example.test/privacy")
    visit listing_path
    page.execute_script(<<~JS)
      window.originalFetch = window.fetch;
      window.pushRequests = 0;
      window.fetch = async (url, options) => {
        const response = await window.originalFetch(url, options);
        if (String(url).endsWith("/push") && response.status === 202)
          document.body.dataset.pushAccepted = String(++window.pushRequests);
        return response;
      };
    JS
    fill_in "store_listing_description", with: "Ready for the store"
    click_button "Push to App Store", exact: false
    within("#global-confirm-dialog") { click_button "Push", exact: true }
    expect(page).to have_content("Pushing changes")
    expect(page).to have_css('body[data-push-accepted="1"]')
    expect(english.reload.description).to eq("Ready for the store")
    english.update!(push_status: "success")
    german.update!(push_status: "failed", push_error: "Retry this locale")
    expect(page).to have_content("de-DE: Retry this locale", wait: 6)
    expect(page).to have_button("Push to App Store", disabled: false)
    click_button "Push to App Store", exact: false
    within("#global-confirm-dialog") { click_button "Push", exact: true }
    expect(page).to have_content("Pushing changes")
    expect(page).to have_css('body[data-push-accepted="2"]')
    expect(german.reload.push_status).to eq("pushing")
  end

  it "renders listing fields as read-only for a viewer" do
    viewer = create(:user, last_organization: organization)
    organization.memberships.create!(user: viewer, role: :viewer)
    sign_in viewer
    visit listing_path
    expect(page).to have_field("store_listing_description", disabled: true)
    expect(page).not_to have_button("Save", exact: true)
    expect(page).not_to have_button("Sync from Store")
    expect(page).not_to have_button("Push to App Store")
    expect(page).not_to have_selector("summary", text: "Add Locale")
  end

  it "keeps locale tabs readable at phone width" do
    page.driver.browser.manage.window.resize_to(390, 844)
    visit listing_path("de-DE")
    english_link = find_link("en-US", exact: true)
    german_link = find_link("de-DE", exact: true)
    bounds = page.evaluate_script("Array.from(arguments).map(el => { const r = el.getBoundingClientRect(); return [r.left, r.right] })", english_link, german_link)
    expect(bounds.flatten.min).to be >= 0
    expect(bounds.flatten.max).to be <= 390
    expect(page).to have_field("store_listing_description", with: german.description)
  ensure
    page.driver.browser.manage.window.resize_to(1400, 900)
  end

  def listing_path(locale = "en-US")
    organization_release_path(organization, "apple_app_#{app.id}", tab: "listing", locale: locale)
  end

  it "shows primary-locale save feedback and keeps the latest edit when requests are slow" do
    visit listing_path
    page.execute_script(<<~JS)
      window.originalFetch = window.fetch;
      window.saveRequests = 0;
      window.fetch = async (url, options) => {
        if (options?.method === "PATCH") {
          window.saveRequests++;
          if (window.saveRequests === 1) await new Promise(resolve => setTimeout(resolve, 1200));
        }
        return window.originalFetch(url, options);
      };
    JS
    fill_in "store_listing_description", with: "First edit"
    find("h1").click
    fill_in "store_listing_description", with: "Latest edit"
    click_link "de-DE", exact: true
    expect(page).to have_current_path(listing_path("de-DE"))
    expect(page).to have_css("#store-listing-editor-#{german.id}")
    click_link "en-US", exact: true
    expect(page).to have_field("store_listing_description", with: "Latest edit")
    expect(page).to have_css('[data-store-listing-editor-target="savingIndicator"]', text: "Saved")
    page.refresh
    expect(page).to have_field("store_listing_description", with: "Latest edit")
    expect(english.reload.description).to eq("Latest edit")
  end

  it "retains a failed draft when switching locales, then saves it after recovery" do
    visit listing_path
    page.execute_script(<<~JS)
      window.originalFetch = window.fetch;
      window.fetch = (url, options) => options?.method === "PATCH"
        ? Promise.resolve(new Response(JSON.stringify({ errors: ["Temporary save failure"] }),
            { status: 422, headers: { "Content-Type": "application/json" } }))
        : window.originalFetch(url, options);
    JS
    fill_in "store_listing_description", with: "Keep my draft"
    click_link "de-DE", exact: true
    expect(page).to have_content("Temporary save failure")
    expect(page).to have_current_path(listing_path)
    expect(page).to have_field("store_listing_description", with: "Keep my draft")
    page.execute_script("window.fetch = window.originalFetch")
    click_link "de-DE", exact: true
    expect(page).to have_current_path(listing_path("de-DE"))
    expect(page).to have_css("#store-listing-editor-#{german.id}")
    click_link "en-US", exact: true
    expect(page).to have_css("#store-listing-editor-#{english.id}")
    expect(page).to have_field("store_listing_description", with: "Keep my draft")
    page.refresh
    expect(page).to have_field("store_listing_description", with: "Keep my draft")
    expect(english.reload.description).to eq("Keep my draft")
  end

  it "offers Google Play locale codes and persists a newly added Japanese listing" do
    android = create(:android_app, organization: organization, default_language: "en-US")
    create(:store_listing, organization: organization, listable: android, locale: "en-US")
    visit organization_release_path(organization, "android_app_#{android.id}", tab: "listing")
    find("summary", text: "Add Locale").click
    select "ja-JP", from: "locale"
    click_button "Add Locale"
    expect(page).to have_content("Editing: ja-JP")
    fill_in "store_listing_short_description", with: "Japanese draft"
    find("h1").click
    expect(page).to have_css('[data-store-listing-editor-target="savingIndicator"]', text: "Saved")
    page.refresh
    expect(page).to have_field("store_listing_short_description", with: "Japanese draft")
    expect(android.store_listings.find_by!(locale: "ja-JP").short_description).to eq("Japanese draft")
  end
end
