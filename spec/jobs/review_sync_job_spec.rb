require "rails_helper"

RSpec.describe ReviewSyncJob, type: :job do
  let(:organization) { create(:organization) }

  describe "#perform" do
    it "enqueues without error" do
      expect { described_class.perform_later(organization_id: organization.id) }
        .to have_enqueued_job(described_class)
    end

    it "returns early for non-existent organization" do
      expect { described_class.new.perform(organization_id: -1) }.not_to raise_error
    end

    context "when review monitoring is disabled" do
      before do
        allow_any_instance_of(Pricing::Entitlements)
          .to receive(:review_monitoring_enabled?).and_return(false)
      end

      it "does not attempt sync" do
        expect(AppStoreConnect::Client).not_to receive(:new)
        expect(GooglePlay::Client).not_to receive(:new)
        described_class.new.perform(organization_id: organization.id)
      end
    end
  end
end
