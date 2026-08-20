require "rails_helper"

# System-level coverage of the Apple Search Ads connection flow (Task 17).
# Complements the request spec (spec/requests/apple_ads_credentials_spec.rb)
# by exercising the browser-side form + the Keywords-tab connection banner.
# The OAuth roundtrip is stubbed so specs stay hermetic.
RSpec.describe "Apple Search Ads connection", type: :system, js: true do
  let(:user) { create(:user, :pro_plan) }
  let(:org)  { create(:organization, owner: user) }
  let!(:app) { create(:apple_app, organization: org) }
  let(:pem)  { SpecCredentialFixtures.ec_private_key }

  before do
    sign_in user
    @mock_client = instance_double(Aso::AppleAds::Client)
    allow(Aso::AppleAds::Client).to receive(:new).and_return(@mock_client)
    allow(@mock_client).to receive(:access_token).and_return("test-token")
  end

  it "shows the connect banner on Keywords show page when no credential exists" do
    visit organization_keyword_path(org, "apple_app_#{app.id}")
    expect(page).to have_content("Connect Apple Search Ads")
    # Connect CTA is a <button> that opens the connect modal (not a link —
    # links navigate away, the modal stays in context).
    expect(page).to have_button("Connect now \u2192")
  end

  it "completes the connection flow from new -> keywords page" do
    visit new_organization_apple_ads_credential_path(org)
    expect(page).to have_content("Connect Apple Search Ads")

    fill_in "Client ID", with: "SEARCHADS.00000000-0000-0000-0000-000000000000"
    fill_in "Team ID (Org ID)", with: "1234567890"
    fill_in "Key ID", with: "ABCDEF1234"
    fill_in "Private Key (PEM)", with: pem
    click_button "Connect & verify"

    # Controller redirects to the keywords index with a "connected" flash notice.
    expect(page).to have_content("connected", wait: 5)
  end

  it "renders the failure banner when OAuth credentials are rejected" do
    allow(@mock_client).to receive(:access_token)
      .and_raise(Aso::AppleAds::CredentialsInvalid, "401 Unauthorized")

    visit new_organization_apple_ads_credential_path(org)
    fill_in "Client ID", with: "SEARCHADS.00000000-0000-0000-0000-000000000000"
    fill_in "Team ID (Org ID)", with: "1234567890"
    fill_in "Key ID", with: "ABCDEF1234"
    fill_in "Private Key (PEM)", with: pem
    click_button "Connect & verify"

    expect(page).to have_content("Connection test failed", wait: 5)
  end

  it "does NOT re-render the private key in HTML on failure" do
    allow(@mock_client).to receive(:access_token)
      .and_raise(Aso::AppleAds::CredentialsInvalid, "401")

    visit new_organization_apple_ads_credential_path(org)
    fill_in "Client ID", with: "SEARCHADS.00000000-0000-0000-0000-000000000000"
    fill_in "Team ID (Org ID)", with: "1234567890"
    fill_in "Key ID", with: "ABCDEF1234"
    fill_in "Private Key (PEM)", with: pem
    click_button "Connect & verify"

    # After the failure re-render the PEM must not appear anywhere in the HTML —
    # not as a value, not as content. Use page.html (raw body) rather than
    # have_content so we catch value= attributes too.
    expect(page).to have_content("Connection test failed", wait: 5)
    body = page.html
    expect(body).not_to include("BEGIN EC PRIVATE KEY")
    expect(body).not_to include(pem.lines.first.strip)
  end

  it "Free-tier users see an upsell banner instead of the connect CTA" do
    user.update!(plan_tier: :free)
    org.reload.reset_entitlements_memo!
    visit organization_keyword_path(org, "apple_app_#{app.id}")
    expect(page).to have_content(/Pro/i)
    # Neither the old link nor the new modal-triggering button should appear.
    expect(page).not_to have_link("Connect now \u2192")
    expect(page).not_to have_button("Connect now \u2192")
  end
end
