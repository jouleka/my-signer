require "rails_helper"

RSpec.describe StoreListingSync::GooglePusher do
  let(:organization) { create(:organization) }
  let(:android_app) { create(:android_app, organization: organization) }
  let(:listing) { create(:store_listing, :android, organization: organization, listable: android_app, whats_new: "New features") }
  let(:client) { instance_double(GooglePlay::Client) }
  let(:listings) { instance_double(GooglePlay::Listings) }

  before do
    create(:google_play_credential, organization: organization, active: true,
      service_account_json: { type: "service_account", project_id: "qa", private_key: "fake", client_email: "qa@example.test", client_id: "qa" }.to_json)
    allow(GooglePlay::Client).to receive(:new).and_return(client)
    allow(GooglePlay::Listings).to receive(:new).and_return(listings)
    allow(listings).to receive(:update)
    allow(client).to receive(:create_edit).and_raise("Track unavailable")
  end

  it "reports a partial push when metadata succeeds but release notes fail" do
    result = described_class.new(organization: organization, store_listing: listing).push!
    expect(result[:status]).to eq("partial_success")
    expect(listing.reload.sync_status).to eq("partially_synced")
    expect(listing.push_fields_skipped).to include("whats_new")
  end

  it "sends an explicitly cleared description instead of silently keeping the store value" do
    listing.update!(description: "")
    expect(listings).to receive(:update).with(android_app.package_name,
      locale: listing.locale, title: listing.app_name, short_description: listing.short_description, full_description: "")
    described_class.new(organization: organization, store_listing: listing).push!
    expect(listing.reload.push_fields_skipped).not_to include("description")
  end
end
