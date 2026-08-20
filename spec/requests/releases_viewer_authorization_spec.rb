require "rails_helper"

# Locks in the contract that viewers (lowest role) cannot perform write
# actions in ReleasesController. This matches the permissions matrix
# rendered on the Permissions page.
RSpec.describe "Releases viewer authorization", type: :request do
  # We use a Team-tier owner so we can have multiple seats (Pro=1 seat would
  # block adding a viewer member at all).
  let(:owner)    { create(:user, :team_plan) }
  let(:viewer)   { create(:user, email: "viewer-rls@example.com") }
  let(:org)      { create(:organization, owner: owner) }
  let(:apple_app) { create(:apple_app, organization: org) }
  let(:apple_release_id) { "apple_app_#{apple_app.id}" }

  before do
    org.memberships.create!(user: viewer, role: :viewer)
    sign_in viewer, scope: :user
  end

  it "blocks viewers from triggering store sync" do
    post sync_organization_release_path(org, apple_release_id)
    expect(response).not_to have_http_status(:ok)
    expect(response).to be_redirect
  end

  it "blocks viewers from pushing to the store" do
    post push_organization_release_path(org, apple_release_id)
    expect(response).not_to have_http_status(:ok)
    expect(response).to be_redirect
  end

  it "blocks viewers from creating a store listing" do
    post create_listing_organization_release_path(org, apple_release_id), params: { locale: "en-US" }
    expect(response).not_to have_http_status(:ok)
    expect(response).to be_redirect
  end

  it "blocks viewers from adding a locale" do
    post add_locale_organization_release_path(org, apple_release_id), params: { locale: "fr-FR" }
    expect(response).not_to have_http_status(:ok)
    expect(response).to be_redirect
  end

  it "blocks viewers from creating a release note" do
    post create_release_note_organization_release_path(org, apple_release_id), params: { release_note: { rendered_text: "..." } }
    expect(response).not_to have_http_status(:ok)
    expect(response).to be_redirect
  end

  it "blocks viewers from triggering AI translate" do
    post translate_organization_release_path(org, apple_release_id), params: { locale: "fr-FR" }
    expect(response).not_to have_http_status(:ok)
    expect(response).to be_redirect
  end

  it "STILL allows viewers to read the releases index/show" do
    get organization_releases_path(org)
    expect(response).to have_http_status(:ok)

    get organization_release_path(org, apple_release_id)
    expect(response).to have_http_status(:ok)
  end
end
