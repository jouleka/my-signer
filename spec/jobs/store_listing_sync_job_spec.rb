require "rails_helper"

RSpec.describe StoreListingSyncJob, type: :job do
  include ActiveJob::TestHelper
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

  it "does not import an app belonging to another organization" do
    other = create(:organization)
    expect(StoreListingSync::AppleImporter).not_to receive(:new)
    described_class.perform_now(organization_id: other.id, listable_type: "AppleApp", listable_id: apple_app.id)
  end

  it "records a terminal sync failure after the final retry" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    status = StoreListingSync::OperationStatus.new(apple_app)
    operation = status.start
    expect(StoreListingSync::AppleImporter).to receive(:new).exactly(3).times.and_raise("Store unavailable")
    expect do
      perform_enqueued_jobs(only: described_class) do
        described_class.perform_later(organization_id: organization.id, listable_type: "AppleApp",
          listable_id: apple_app.id, operation_id: operation[:id])
      end
    end.to raise_error(Minitest::UnexpectedError)
    expect(status.read).to include(status: "failed", error: "Store unavailable")
  end
end
