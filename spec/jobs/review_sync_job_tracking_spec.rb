require "rails_helper"

RSpec.describe ReviewSyncJob, "tracking", type: :job do
  let(:organization) { create(:organization) }

  before do
    allow_any_instance_of(Pricing::Entitlements)
      .to receive(:review_monitoring_enabled?).and_return(true)
    allow_any_instance_of(Pricing::Entitlements)
      .to receive(:max_review_monitoring_apps).and_return(5)
    allow(ReviewSync::Performer).to receive(:new).and_return(
      instance_double(ReviewSync::Performer, call: nil)
    )
  end

  it "records a run entry with status ok after success" do
    described_class.perform_now(organization_id: organization.id)
    run = OrgSyncRun.find_by(organization: organization, job_name: "reviews")
    expect(run.status).to eq("ok")
  end

  it "records a run entry with status error on failure" do
    # ActiveJob's retry_on catches the re-raised error and schedules retries,
    # so perform_now does not surface it. The row must still reflect the error.
    allow(ReviewSync::Performer).to receive(:new).and_raise(StandardError, "downstream")
    described_class.perform_now(organization_id: organization.id)

    run = OrgSyncRun.find_by(organization: organization, job_name: "reviews")
    expect(run.status).to eq("error")
    expect(run.error_message).to eq("downstream")
  end
end
