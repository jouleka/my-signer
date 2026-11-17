require "rails_helper"

RSpec.describe "Release workflow", type: :system, js: true do
  include ActiveJob::TestHelper
  let(:user) { create(:user, :team_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:app) { create(:apple_app, organization: organization) }
  let!(:version) { create(:app_store_version, organization: organization, apple_app: app, version_string: "2.0.0") }
  let!(:listing) { create(:store_listing, organization: organization, listable: app, locale: "en-US") }
  let!(:german) { create(:store_listing, organization: organization, listable: app, locale: "de-DE") }
  let!(:note) { create(:release_note, organization: organization, listable: app, version_string: "2.0.0", template_data: {}, rendered_text: "Original freeform note", translations: { "de-DE" => "Eine einfache Nachricht" }) }

  before do
    user.update!(last_organization: organization)
    sign_in user
  end

  def release_path(tab = "whats_new", **options)
    organization_release_path(organization, "apple_app_#{app.id}", tab: tab, **options)
  end

  def saved
    expect(page).to have_css('[data-locale-switcher-target="savingIndicator"]', text: "Saved")
  end

  it "preserves freeform content in the preview and across locale switches and reload" do
    visit release_path
    expect(page).to have_css('[data-release-note-editor-target="preview"]', text: "Original freeform note")
    find('[data-locale-switcher-target="selector"]').select("de-DE")
    expect(page).to have_css('[data-locale-switcher-target="translationPreview"][data-locale="de-DE"]', text: "Eine einfache Nachricht")
    within('[data-locale-switcher-target="panel"][data-locale="de-DE"]') do
      click_button "Freeform"
      expect(find('[data-translation-editor-target="freeformInput"]').value).to eq("Eine einfache Nachricht")
    end
  end

  it "saves the latest text before applying it to listings" do
    visit release_path
    find('[data-release-note-editor-target="freeformInput"]').fill_in with: "Latest release note"
    click_button "Apply to Listings"
    within("#global-confirm-dialog") { click_button "Yes, continue" }
    expect(page).to have_content("Applied to store listings")
    expect(listing.reload.whats_new).to eq("Latest release note")
    page.refresh
    expect(find('[data-release-note-editor-target="freeformInput"]').value).to eq("Latest release note")
  end

  it "persists removing the last template bullet" do
    note.update!(template_data: { "new" => [ "A new feature" ] }, rendered_text: "NEW\n- A new feature")
    visit release_path
    within('[data-release-note-editor-target="newList"]') do
      find('[data-action="click->release-note-editor#removeItem"]').click
    end
    saved
    page.refresh
    expect(note.reload.rendered_text).to be_blank
    expect(page).not_to have_field(with: "A new feature")
  end

  it "reports validation errors and saves corrections without losing the draft" do
    visit release_path
    find('[data-release-note-editor-target="freeformInput"]').fill_in with: "x" * 4001
    expect(page).to have_content("maximum is 4000")
    expect(find('[data-release-note-editor-target="freeformInput"]').value.length).to eq(4001)
    find('[data-release-note-editor-target="freeformInput"]').fill_in with: "Corrected text"
    saved
    page.refresh
    expect(note.reload.rendered_text).to eq("Corrected text")
  end

  it "persists checking and unchecking the same item without reloading between clicks" do
    visit release_path("checklist")
    checkbox = find('[data-release-checklist-key-param="release_notes_written"]')
    checkbox.check
    expect(page).to have_css('[data-release-checklist-key-param="release_notes_written"]:not(:disabled)')
    checkbox.uncheck
    expect(page).to have_css('[data-release-checklist-key-param="release_notes_written"]:not(:disabled)')
    page.refresh
    expect(find('[data-release-checklist-key-param="release_notes_written"]')).not_to be_checked
  end

  it "keeps a viewer's notes and checklist read only" do
    viewer = create(:user, last_organization: organization)
    create(:membership, organization: organization, user: viewer, role: :viewer)
    sign_out user
    sign_in viewer
    visit release_path
    expect(page).not_to have_button("Apply to Listings")
    expect(find('[data-release-note-editor-target="freeformInput"]')).to be_disabled
    visit release_path("checklist")
    expect(page).to have_css('[data-checklist-item] input[type="checkbox"]:disabled', count: 6)
    expect(page).not_to have_field("label")
  end

  it "saves version, base text and translation before leaving the editor" do
    visit release_path
    fill_in "release_note_version_string", with: "2.1.0"
    find('[data-release-note-editor-target="freeformInput"]').fill_in with: "Both forms saved"
    find('[data-locale-switcher-target="selector"]').select("de-DE")
    find('[data-translation-editor-target="freeformInput"]').fill_in with: "Neue deutsche Notiz"
    click_link "History", exact: true
    expect(page).to have_content("v2.1.0")
    expect(note.reload.version_string).to eq("2.1.0")
    expect(note.rendered_text).to eq("Both forms saved")
    expect(note.translations["de-DE"]).to eq("Neue deutsche Notiz")
  end

  it "supports requesting changes, editing, resubmitting, approval and application" do
    create(:membership, organization: organization, user: create(:user), role: :developer)
    visit release_path
    click_button "Submit for Review"
    within("#global-confirm-dialog") { click_button "Yes, continue" }
    expect(page).to have_content("Awaiting review")
    expect(find('[data-release-note-editor-target="freeformInput"]')).to be_disabled
    click_button "Request Changes"
    within("#reject-review-modal") do
      fill_in "comment", with: "Mention the new search"
      click_button "Send"
    end
    expect(page).to have_content("Changes requested")
    find('[data-release-note-editor-target="freeformInput"]').fill_in with: "New search is available"
    click_button "Submit for Review"
    within("#global-confirm-dialog") { click_button "Yes, continue" }
    expect(page).to have_content("Awaiting review")
    click_button "Approve", exact: true
    expect(page).to have_content("Approved by")
    click_button "Apply to Listings"
    within("#global-confirm-dialog") { click_button "Yes, continue" }
    expect(page).to have_content("Applied to store listings")
    expect(listing.reload.whats_new).to eq("New search is available")
    expect(german.reload.whats_new).to eq("Eine einfache Nachricht")
    page.refresh
    expect(note.reload.status).to eq("applied")
  end

  it "adds a required custom item, reports duplicates and removes it" do
    visit release_path("checklist")
    fill_in "label", with: "Confirm screenshots"
    find('input[name="required"]').check
    click_button "Add", exact: true
    expect(page).to have_css('[data-checklist-item]', text: "Confirm screenshots")
    fill_in "label", with: "Confirm screenshots"
    click_button "Add", exact: true
    expect(page).to have_content("blank or duplicate")
    within('[data-checklist-item]', text: "Confirm screenshots") { find('button[aria-label="Remove custom item"]').click }
    expect(page).not_to have_css('[data-checklist-item]', text: "Confirm screenshots")
    page.refresh
    expect(page).not_to have_css('[data-checklist-item]', text: "Confirm screenshots")
  end

  it "keeps failed checklist changes visible and can retry" do
    visit release_path("checklist")
    page.execute_script(<<~JS)
      window.originalFetch = window.fetch;
      window.fetch = (url, options) => String(url).includes("check_item")
        ? Promise.resolve(new Response(JSON.stringify({ error: "Unavailable" }), { status: 503 }))
        : window.originalFetch(url, options);
    JS
    find('[data-release-checklist-key-param="release_notes_written"]').check
    expect(page).to have_content("Could not save checklist")
    expect(find('[data-release-checklist-key-param="release_notes_written"]')).not_to be_checked
    page.execute_script("window.fetch = window.originalFetch")
    find('[data-release-checklist-key-param="release_notes_written"]').check
    expect(page).to have_css('[data-release-checklist-key-param="release_notes_written"]:not(:disabled)')
    page.refresh
    expect(find('[data-release-checklist-key-param="release_notes_written"]')).to be_checked
  end

  it "shows translation progress through reload and reports failure before a successful retry" do
    client = instance_double(OpenAI::Client)
    allow(OpenAI::Client).to receive(:new).and_return(client)
    allow(Rails.application.credentials).to receive(:dig).with(:openai, :api_key).and_return("test-key")
    allow(client).to receive(:chat).and_raise(Faraday::ConnectionFailed, "Translation service unavailable")
    visit release_path
    click_button "Translate to all locales", exact: false
    within("#global-confirm-dialog") { click_button "Yes, continue" }
    expect(page).to have_css('#translate-button button[aria-busy="true"]')
    page.refresh
    expect(page).to have_css('#translate-button button[aria-busy="true"]')
    expect(find('[data-release-note-editor-target="freeformInput"]')).to be_disabled
    perform_enqueued_jobs(only: ReleaseNoteTranslationJob)
    page.refresh
    expect(page).to have_content("Translation service unavailable")
    expect(organization.reload.ai_translations_count).to eq(0)
    allow(client).to receive(:chat).and_return("choices" => [ { "message" => { "content" => { translated_text: "Erfolgreich übersetzt" }.to_json } } ])
    click_button "Translate to all locales", exact: false
    within("#global-confirm-dialog") { click_button "Yes, continue" }
    expect(page).to have_css('#translate-button button[aria-busy="true"]')
    perform_enqueued_jobs(only: ReleaseNoteTranslationJob)
    page.refresh
    find('[data-locale-switcher-target="selector"]').select("de-DE")
    expect(find('[data-translation-editor-target="freeformInput"]').value).to eq("Erfolgreich übersetzt")
    expect(organization.reload.ai_translations_count).to eq(1)
  end

  it "shows rewrite failure and preserves the original note and quota" do
    rewriter = instance_double(ReleaseNotes::AiRewriter)
    allow(ReleaseNotes::AiRewriter).to receive(:new).and_return(rewriter)
    allow(rewriter).to receive(:rewrite!).and_raise("Rewrite service unavailable")
    visit release_path
    click_button "AI Rewrite", exact: false
    within("#ai-rewrite-modal") do
      fill_in "raw_input", with: "Fix search crashes"
      click_button "Rewrite with AI"
    end
    expect(page).to have_css('#ai-rewrite-button button[aria-busy="true"]')
    page.refresh
    expect(page).to have_css('#ai-rewrite-button button[aria-busy="true"]')
    expect { perform_enqueued_jobs(only: ReleaseNoteRewriteJob) }.to raise_error("Rewrite service unavailable")
    page.refresh
    expect(page).to have_content("Rewrite service unavailable")
    expect(page).to have_button("AI Rewrite", exact: false, disabled: false)
    expect(note.reload.rendered_text).to eq("Original freeform note")
    expect(organization.reload.ai_rewrites_count).to eq(0)
  end

  it "submits the chosen local release time, reports a store failure, and retries automatically" do
    create(:app_store_connect_credential, organization: organization)
    build = create(:apple_build, organization: organization, apple_app: app)
    version.update!(apple_build: build, app_store_state: "PREPARE_FOR_SUBMISSION")
    listing.update!(privacy_policy_url: "https://example.test/privacy", support_url: "https://example.test/support")
    client = instance_double(AppStoreConnect::Client)
    service = instance_double(AppStoreConnect::Versions)
    allow(AppStoreConnect::Client).to receive(:new).and_return(client)
    allow(AppStoreConnect::Versions).to receive(:new).and_return(service)
    allow(service).to receive(:update_release_settings)
    allow(service).to receive(:validation_errors).and_return([])
    allow(service).to receive(:submit_for_review).and_raise("Store temporarily unavailable")
    page.driver.browser.execute_cdp("Emulation.setTimezoneOverride", timezoneId: "Europe/Tirane")
    visit release_path("submission")
    find('input[value="SCHEDULED"]').choose
    page.execute_script(<<~JS)
      const input = document.querySelector('[data-submission-form-target="date"]');
      input.value = "2030-01-12T10:00";
      input.dispatchEvent(new Event("input", { bubbles: true }));
    JS
    click_button "Submit for Review"
    within("#global-confirm-dialog") { click_button "Yes, continue" }
    expect(page).to have_css('[data-submission-active="true"]')
    perform_enqueued_jobs(only: AppStoreSubmitJob)
    expect(service).to have_received(:update_release_settings).with(version_id: version.version_id, release_type: "SCHEDULED", earliest_release_date: "2030-01-12T09:00:00Z")
    page.refresh
    expect(page).to have_content("Last submission failed")
    expect(page).to have_content("Store temporarily unavailable")
    allow(service).to receive(:submit_for_review).and_return("submission_id" => "qa-review", "reused" => false)
    find('input[value="AFTER_APPROVAL"]').choose
    click_button "Submit for Review"
    within("#global-confirm-dialog") { click_button "Yes, continue" }
    expect(page).to have_css('[data-submission-active="true"]')
    perform_enqueued_jobs(only: AppStoreSubmitJob)
    page.refresh
    expect(page).to have_content("Waiting For Review")
    expect(version.reload.submission_status).to eq("submitted")
  ensure
    page.driver.browser.execute_cdp("Emulation.setTimezoneOverride", timezoneId: "")
  end

  it "clears the visible approval after edits and asks for another review" do
    create(:membership, organization: organization, user: create(:user), role: :developer)
    note.submit_for_review!(user: user)
    note.approve_review!(user: user, comment: "Good to ship")
    visit release_path
    expect(page).to have_content("Approved by")
    find('[data-release-note-editor-target="freeformInput"]').fill_in with: "An unreviewed change"
    expect(page).to have_content("Submit them for review again before applying")
    expect(page).not_to have_content("Approved by")
    expect(page).to have_button("Apply to Listings", disabled: true)
  end

  it "keeps the mobile review message and buttons on separate rows" do
    create(:membership, organization: organization, user: create(:user), role: :developer)
    note.submit_for_review!(user: user)
    page.driver.browser.manage.window.resize_to(390, 844)
    visit release_path
    expect(page).to have_content("Awaiting review")
    bounds = page.evaluate_script(<<~JS)
      (() => {
        const message = [...document.querySelectorAll("p")].find(el => el.textContent.includes("Submitted for review"));
        const approve = [...document.querySelectorAll("button")].find(el => el.textContent.trim() === "Approve");
        return { messageBottom: message.getBoundingClientRect().bottom, approveTop: approve.getBoundingClientRect().top };
      })()
    JS
    expect(bounds["approveTop"]).to be >= bounds["messageBottom"]
  ensure
    page.driver.browser.manage.window.resize_to(1400, 900)
  end

  it "validates Android notes at 500 characters and preserves emoji counts" do
    android = create(:android_app, organization: organization)
    android_note = create(:release_note, organization: organization, listable: android, version_string: "100", template_data: {}, rendered_text: "Android update")
    create(:play_store_release, android_app: android, version_code: "100", status: "submitted")
    visit organization_release_path(organization, "android_app_#{android.id}", tab: "whats_new")
    find('[data-release-note-editor-target="freeformInput"]').fill_in with: "x" * 501
    expect(page).to have_content("maximum is 500")
    find('[data-release-note-editor-target="freeformInput"]').fill_in with: "📱" * 500
    saved
    page.refresh
    expect(android_note.reload.rendered_text.length).to eq(500)
    expect(page).to have_css('[data-release-note-editor-target="charCount"]', text: "500/500")
    click_link "Submission", exact: false
    expect(page).to have_content("Play Console")
    expect(page).not_to have_button("Submit for Review")
  end

  it "creates the first note before store sync, opens its history and deletes it" do
    version.destroy!
    note.destroy!
    visit release_path
    click_button "Create Release Note"
    expect(page).to have_css('[data-release-note-editor-target="freeformInput"]')
    find('[data-release-note-editor-target="freeformInput"]').fill_in with: "First release draft"
    saved
    click_link "History", exact: true
    click_link "Open", exact: false
    expect(find('[data-release-note-editor-target="freeformInput"]').value).to eq("First release draft")
    click_button "Delete", exact: false
    within("#global-confirm-dialog") { click_button "Yes, continue" }
    expect(page).to have_content("No release notes yet")
    page.refresh
    expect(organization.release_notes.for_app(app)).to be_empty
  end
end
