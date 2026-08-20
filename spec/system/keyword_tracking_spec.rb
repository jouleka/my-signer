require "rails_helper"

RSpec.describe "Keyword tracking tab", type: :system, js: true do
  let(:user) { create(:user, :pro_plan) }
  let(:org)  { create(:organization, owner: user) }
  let(:app)  { create(:apple_app, organization: org, name: "My App") }

  before { sign_in user }

  it "shows empty state when no keywords tracked" do
    visit organization_keyword_path(org, "apple_app_#{app.id}", tab: "tracking")
    # The label is uppercased via CSS (LABEL_UPPERCASE). Headless Chrome may
    # return either the CSS-rendered form ("NO KEYWORDS TRACKED YET") or the
    # DOM source text ("No keywords tracked yet") depending on driver/version,
    # so match case-insensitively to be robust across local + CI.
    expect(page).to have_content(/no keywords tracked yet/i)
    expect(page).to have_content("Add a keyword to start monitoring its rank")
  end

  it "adds a tracked keyword via modal and shows a card" do
    visit organization_keyword_path(org, "apple_app_#{app.id}", tab: "tracking")
    click_button "Add keyword"

    # The modal opens; Keyword field becomes available.
    expect(page).to have_field("Keyword")

    fill_in "Keyword", with: "photo editor"
    find("label", text: /\bUS\b/).click
    click_button "Track keyword"

    expect(page).to have_content("photo editor", wait: 5)
    expect(page).to have_content("US", wait: 5)
  end

  it "prevents selecting more than 3 countries on Pro tier" do
    visit organization_keyword_path(org, "apple_app_#{app.id}", tab: "tracking")
    click_button "Add keyword"

    %w[US GB DE AU].each { |code| find("label", text: /\b#{code}\b/).click }
    checked = page.evaluate_script("document.querySelectorAll('[data-country-checkbox]:checked').length")
    expect(checked).to eq(3)
  end
end
