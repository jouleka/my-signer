require "rails_helper"

RSpec.describe AppStoreConnectSyncJob, type: :job do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }

  describe "#perform" do
    it "calls AppStoreConnect::Sync when organization exists" do
      sync_instance = instance_double(AppStoreConnect::Sync, call: nil)
      expect(AppStoreConnect::Sync).to receive(:new).with(organization: organization).and_return(sync_instance)
      expect(sync_instance).to receive(:call)

      described_class.perform_now(organization.id)
    end

    it "silently returns when organization is not found" do
      expect(AppStoreConnect::Sync).not_to receive(:new)
      described_class.perform_now(-1)
    end

    it "uses advisory locking to prevent concurrent syncs" do
      connection = ActiveRecord::Base.connection
      lock_id = Zlib.crc32("asc:sync:org:#{organization.id}")

      # Simulate lock already held
      expect(connection).to receive(:select_value)
        .with("SELECT pg_try_advisory_lock(#{lock_id})")
        .and_return(false)

      expect(AppStoreConnect::Sync).not_to receive(:new)
      described_class.perform_now(organization.id)
    end
  end
end
