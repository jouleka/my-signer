require "rails_helper"

RSpec.describe StoreListingSyncJob, type: :job do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) { create(:apple_app, organization: organization) }

  it "queues the job" do
    expect {
      described_class.perform_later(
        organization_id: organization.id,
        listable_type: "AppleApp",
        listable_id: apple_app.id
      )
    }.to have_enqueued_job(described_class)
  end

  it "calls AppleImporter for AppleApp" do
    importer = instance_double(StoreListingSync::AppleImporter)
    allow(StoreListingSync::AppleImporter).to receive(:new).and_return(importer)
    allow(importer).to receive(:import!).and_return([])

    # Create credential so importer can initialize
    create(:app_store_connect_credential, organization: organization)

    described_class.perform_now(
      organization_id: organization.id,
      listable_type: "AppleApp",
      listable_id: apple_app.id
    )

    expect(StoreListingSync::AppleImporter).to have_received(:new)
    expect(importer).to have_received(:import!)
  end
end
