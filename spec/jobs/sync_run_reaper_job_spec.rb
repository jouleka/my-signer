require "rails_helper"

RSpec.describe SyncRunReaperJob do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:threshold) { described_class::STALE_AFTER }

  def make_run(job_name, status:, started:, finished: nil, err: nil, org: organization)
    OrgSyncRun.create!(
      organization: org,
      job_name: job_name,
      status: status,
      started_at: started,
      finished_at: finished,
      error_message: err
    )
  end

  describe "#perform" do
    it "marks a stranded running row older than STALE_AFTER as error" do
      stale = make_run("asc", status: "running", started: (threshold + 1.minute).ago)

      described_class.new.perform

      stale.reload
      expect(stale.status).to eq("error")
      expect(stale.finished_at).to be_within(5.seconds).of(Time.current)
      expect(stale.error_message).to eq(described_class::REAPER_ERROR_MESSAGE)
    end

    it "is kept in sync with the aggregator's staleness window" do
      expect(described_class::STALE_AFTER).to eq(Sync::StatusAggregator::STALE_RUN_THRESHOLD)
    end

    it "leaves fresh running rows alone (still within the threshold)" do
      fresh = make_run("asc", status: "running", started: (threshold - 1.minute).ago)

      described_class.new.perform

      fresh.reload
      expect(fresh.status).to eq("running")
      expect(fresh.finished_at).to be_nil
      expect(fresh.error_message).to be_nil
    end

    it "leaves terminal rows alone regardless of age" do
      ok   = make_run("asc",     status: "ok",      started: 2.hours.ago, finished: 2.hours.ago)
      err  = make_run("reviews", status: "error",   started: 2.hours.ago, finished: 2.hours.ago, err: "boom")

      described_class.new.perform

      expect(ok.reload.status).to eq("ok")
      expect(err.reload.status).to eq("error")
      expect(err.error_message).to eq("boom")
    end

    it "reaps stranded rows across multiple organizations in one pass" do
      a = make_run("asc",     status: "running", started: (threshold + 2.minutes).ago)
      b = make_run("reviews", status: "running", started: (threshold + 5.minutes).ago, org: other_organization)

      count = described_class.new.perform

      expect(count).to eq(2)
      expect(a.reload.status).to eq("error")
      expect(b.reload.status).to eq("error")
    end

    it "is idempotent: a second run touches nothing" do
      make_run("asc", status: "running", started: (threshold + 1.minute).ago)
      described_class.new.perform

      expect(described_class.new.perform).to eq(0)
    end

    it "does nothing when there are no rows at all" do
      expect { described_class.new.perform }.not_to raise_error
      expect(described_class.new.perform).to eq(0)
    end
  end
end
