require "rails_helper"

RSpec.describe GooglePlaySyncJob, type: :job do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }

  describe "#perform" do
    it "calls GooglePlay::Sync when organization exists" do
      sync_instance = instance_double(GooglePlay::Sync)
      expect(GooglePlay::Sync).to receive(:new).with(organization: organization).and_return(sync_instance)
      expect(sync_instance).to receive(:sync_all!).with(package_names: nil)

      described_class.perform_now(organization.id)
    end

    it "passes package_names to sync" do
      packages = [ "com.example.app" ]
      sync_instance = instance_double(GooglePlay::Sync)
      expect(GooglePlay::Sync).to receive(:new).with(organization: organization).and_return(sync_instance)
      expect(sync_instance).to receive(:sync_all!).with(package_names: packages)

      described_class.perform_now(organization.id, packages)
    end

    it "silently returns when organization is not found" do
      expect(GooglePlay::Sync).not_to receive(:new)
      described_class.perform_now(-1)
    end

    it "uses advisory locking to prevent concurrent syncs" do
      connection = ActiveRecord::Base.connection
      lock_id = Zlib.crc32("gp:sync:org:#{organization.id}")

      expect(connection).to receive(:select_value)
        .with("SELECT pg_try_advisory_lock(#{lock_id})")
        .and_return(false)

      expect(GooglePlay::Sync).not_to receive(:new)
      described_class.perform_now(organization.id)
    end
  end
end
