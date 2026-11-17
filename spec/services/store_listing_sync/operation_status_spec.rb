require "rails_helper"

RSpec.describe StoreListingSync::OperationStatus do
  let(:app) { create(:apple_app) }
  let(:status) { described_class.new(app) }

  before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

  it "is active while a sync has recently reported progress" do
    operation = status.start
    status.update(operation[:id], status: "running")
    expect(status).to be_active
  end

  it "stops blocking once a queued or running sync is older than 15 minutes" do
    operation = status.start
    travel 16.minutes do
      expect(status).not_to be_active
      expect(status.read).to include(id: operation[:id], status: "failed", error: described_class::STALE_MESSAGE)
    end
  end

  it "keeps a late-reporting job able to record its result" do
    operation = status.start
    travel 16.minutes do
      status.update(operation[:id], status: "completed")
      expect(status.read).to include(status: "completed")
    end
  end
end
