require "rails_helper"
require "webmock/rspec"

RSpec.describe "Dashboard and store connections", type: :system, js: true do
  let(:user) { create(:user, :team_plan) }
  let(:organization) { create(:organization, owner: user) }

  before do
    user.update!(last_organization: organization)
    sign_in user
  end

  it "keeps a healthy active connection healthy after a page reload" do
    create(:app_store_connect_credential, organization: organization,
      last_synced_at: 1.hour.ago, last_sync_status: "ok")
    create(:app_store_connect_credential, organization: organization, active: false,
      last_synced_at: 10.minutes.ago, last_sync_status: "error", last_sync_error: "Retired key failure")

    visit authenticated_root_path
    expect(page).to have_content(organization.name)
    expect(page).not_to have_content("iOS sync failed")
    expect(page).not_to have_content("Sync Apple Data")

    page.refresh
    expect(page).not_to have_content("Retired key failure")
  end

  it "shows a validation message for the wrong JSON shape and allows correction" do
    visit organization_path(organization)
    find('input[aria-label="Android"]').click
    click_button "Add Android credential"

    within("#add_android_credential_modal") do
      fill_in "e.g. Production Service Account", with: "Invalid JSON QA"
      fill_in '{"type": "service_account", ...}', with: "[]"
      click_button "Add Credential"
    end

    expect(page).to have_content("must be a JSON object")
    expect(organization.google_play_credentials.count).to eq(0)
    find('input[aria-label="Android"]').click
    click_button "Add Android credential"
    expect(page).to have_css("#add_android_credential_modal[open]")

    within("#add_android_credential_modal") do
      fill_in "e.g. Production Service Account", with: "Corrected QA connection"
      fill_in '{"type": "service_account", ...}', with: {
        type: "service_account", project_id: "qa", private_key: "test-key",
        client_email: "qa@example.test", client_id: "123"
      }.to_json
      click_button "Add Credential"
    end

    expect(page).to have_content("Google Play credential added")
    page.refresh
    find('input[aria-label="Android"]').click
    expect(page).to have_content("Corrected QA connection")
    expect(organization.google_play_credentials.count).to eq(1)
  end

  it "shows the correct Free history window after reloading" do
    user.update!(plan_tier: :free)
    apple_app = create(:apple_app, organization: organization)
    create(:app_analytics_snapshot, organization: organization, snapshotable: apple_app,
      snapshot_date: Date.current, total_downloads: 137)
    create(:app_analytics_snapshot, organization: organization, snapshotable: apple_app,
      snapshot_date: 10.days.ago.to_date, total_downloads: 8_000)

    visit authenticated_root_path
    within('[aria-label="Analytics overview"]') do
      expect(page).to have_content("137")
      expect(page).to have_content("last 7 days")
      expect(page).not_to have_content("8,137")
    end
    page.refresh
    expect(page).to have_content("last 7 days")
  end

  it "adds, tests, activates and removes an Apple connection through the browser" do
    previous = create(:app_store_connect_credential, organization: organization)
    key = OpenSSL::PKey::EC.generate("prime256v1")
    stub_request(:get, "https://api.appstoreconnect.apple.com/v1/bundleIds")
      .with(query: { "limit" => "1", "fields[bundleIds]" => "seedId" })
      .to_return(status: 200, body: { data: [ { attributes: { seedId: "TEAM12345X" } } ] }.to_json)
    stub_request(:get, "https://api.appstoreconnect.apple.com/v1/certificates")
      .with(query: { "limit" => "1" }).to_return(status: 200, body: { data: [] }.to_json)

    visit organization_path(organization)
    click_button "Add iOS credential"
    within("#add_ios_credential_modal") do
      fill_in "e.g. Production Key", with: "Replacement Apple key"
      fill_in "app_store_connect_credential_key_id", with: "APPLEKEY01"
      fill_in "app_store_connect_credential_issuer_id", with: "11111111-2222-3333-4444-555555555555"
      fill_in "app_store_connect_credential_private_key", with: key.to_pem
      click_button "Add Credential"
    end
    expect(page).to have_content("validated successfully")
    credential = organization.app_store_connect_credentials.find_by!(name: "Replacement Apple key")
    expect(credential).not_to be_active
    page.refresh
    expect(page).to have_content("Replacement Apple key")

    within("form[action='#{test_organization_app_store_connect_credential_path(organization, credential)}']") do
      find('button[title="Test connection"]').click
    end
    expect(page).to have_content("Connection successful")
    expect(credential.reload).not_to be_active
    expect(previous.reload).to be_active

    within("form[action='#{activate_organization_app_store_connect_credential_path(organization, credential)}']") do
      find('button[title="Set as active credential"]').click
    end
    expect(page).to have_content("Credential set active. Syncing...")
    page.refresh
    expect(credential.reload).to be_active
    expect(previous.reload).not_to be_active

    within("form[action='#{organization_app_store_connect_credential_path(organization, credential)}']") do
      find('button[title="Remove credential"]').click
    end
    within("#global-confirm-dialog") { click_button "Yes, continue" }
    expect(page).to have_content("Credential removed")
    page.refresh
    expect(page).not_to have_content("Replacement Apple key")
    expect(organization.app_store_connect_credentials.sole).to eq(previous)
  end

  it "cancels and confirms dismissal of a sync error, persisting the result after reload" do
    run = OrgSyncRun.create!(organization: organization, job_name: "keywords_rank", status: "error",
      started_at: 1.hour.ago, finished_at: 30.minutes.ago, error_message: "Keyword provider unavailable")

    visit authenticated_root_path
    expect(page).to have_content("Keyword provider unavailable")
    click_button "Dismiss"
    within("#global-confirm-dialog") { click_button "Go back" }
    expect(page).to have_content("Keyword provider unavailable")
    expect(OrgSyncRun.exists?(run.id)).to be true

    click_button "Dismiss"
    within("#global-confirm-dialog") { click_button "Yes, continue" }
    expect(page).to have_content("Cleared")
    page.refresh
    expect(page).not_to have_content("Keyword provider unavailable")
    expect(OrgSyncRun.exists?(run.id)).to be false
  end
end
