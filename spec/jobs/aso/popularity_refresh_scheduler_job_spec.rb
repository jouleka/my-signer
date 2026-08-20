require "rails_helper"

RSpec.describe Aso::PopularityRefreshSchedulerJob, type: :job do
  include ActiveJob::TestHelper

  describe "#perform" do
    it "enqueues one PopularityRefreshJob per org with a connected credential" do
      user1 = create(:user, :pro_plan)
      user2 = create(:user, :pro_plan)
      user3 = create(:user, :pro_plan)

      org1 = create(:organization, owner: user1)
      org2 = create(:organization, owner: user2)
      create(:organization, owner: user3) # no credential

      create(:apple_ads_credential, organization: org1, last_successful_at: 1.hour.ago)
      create(:apple_ads_credential, organization: org2, last_successful_at: 1.hour.ago)
      # org3 has no credential

      expect {
        described_class.new.perform
      }.to change { enqueued_jobs.size }.by(2)

      org_ids = enqueued_jobs.map { |j| j[:args].last[:organization_id] || j[:args].last["organization_id"] }
      expect(org_ids).to contain_exactly(org1.id, org2.id)
    end

    it "skips orgs whose credential has never been successful" do
      user = create(:user, :pro_plan)
      org = create(:organization, owner: user)
      create(:apple_ads_credential, organization: org, last_successful_at: nil)

      expect {
        described_class.new.perform
      }.not_to change { enqueued_jobs.size }
    end

    it "staggers enqueues across 20 hours" do
      3.times do
        user = create(:user, :pro_plan)
        org = create(:organization, owner: user)
        create(:apple_ads_credential, organization: org, last_successful_at: 1.hour.ago)
      end

      described_class.new.perform

      waits = enqueued_jobs.map { |j| j[:at] }.compact
      expect(waits).to all(be <= 20.hours.from_now.to_f + 5)
    end
  end
end
