require "rails_helper"

RSpec.describe Sync::StatusAggregator do
  let(:organization) { create(:organization) }

  def make_run(job_name, status, finished: nil, err: nil, started: 10.minutes.ago)
    OrgSyncRun.create!(
      organization: organization,
      job_name: job_name,
      status: status,
      started_at: started,
      finished_at: finished,
      error_message: err
    )
  end

  # Builds a Set of advisory-lock objids as the aggregator would see them,
  # then stubs the probe so we don't have to actually take real pg locks
  # (session-level locks don't roll back with the test transaction).
  def stub_held_locks(aggregator, *job_names_held)
    ids = job_names_held.filter_map do |j|
      key = described_class.advisory_lock_key_for(j, organization.id)
      Zlib.crc32(key) if key
    end
    allow(aggregator).to receive(:fetch_held_advisory_lock_ids).and_return(Set.new(ids))
  end

  it "reports running: false and last_sync_status: ok when no runs exist" do
    payload = described_class.new(organization: organization).payload
    expect(payload[:running]).to be false
    expect(payload[:last_sync_status]).to eq("ok")
    expect(payload[:last_synced_at]).to be_nil
    expect(payload[:jobs]).to eq({})
  end

  it "reports running: true when at least one job is live-running (lock held)" do
    make_run("asc", "ok", finished: 5.minutes.ago)
    make_run("reviews", "running", started: 2.minutes.ago)
    aggregator = described_class.new(organization: organization)
    stub_held_locks(aggregator, :reviews)
    payload = aggregator.payload
    expect(payload[:running]).to be true
    expect(payload[:last_sync_status]).to eq("running")
  end

  it "reports ok when all runs completed successfully" do
    make_run("asc", "ok", finished: 5.minutes.ago)
    make_run("reviews", "ok", finished: 3.minutes.ago)
    payload = described_class.new(organization: organization).payload
    expect(payload[:running]).to be false
    expect(payload[:last_sync_status]).to eq("ok")
    expect(payload[:last_synced_at]).to be_within(10.seconds).of(3.minutes.ago)
  end

  it "reports partial when at least one succeeded and at least one errored" do
    make_run("asc", "ok", finished: 5.minutes.ago)
    make_run("reviews", "error", finished: 3.minutes.ago, err: "boom")
    payload = described_class.new(organization: organization).payload
    expect(payload[:running]).to be false
    expect(payload[:last_sync_status]).to eq("partial")
  end

  it "reports error when every finished run errored" do
    make_run("asc", "error", finished: 5.minutes.ago, err: "nope")
    payload = described_class.new(organization: organization).payload
    expect(payload[:running]).to be false
    expect(payload[:last_sync_status]).to eq("error")
    expect(payload[:last_sync_error]).to eq("nope")
  end

  it "exposes per-job details in the :jobs key" do
    make_run("asc", "ok", finished: 5.minutes.ago)
    make_run("reviews", "error", finished: 3.minutes.ago, err: "downstream")
    payload = described_class.new(organization: organization).payload
    expect(payload[:jobs]["asc"][:status]).to eq("ok")
    expect(payload[:jobs]["reviews"][:status]).to eq("error")
    expect(payload[:jobs]["reviews"][:error_message]).to eq("downstream")
  end

  describe "advisory-lock liveness detection" do
    # Regression: the previous version of this class used a 15-minute
    # time-based staleness window as its only stranding signal, which
    # left the navbar spinner spinning for up to 15 minutes after a
    # `bin/dev` reload killed an in-flight sync. The lock-based probe
    # lets us detect a dead worker immediately.
    let(:grace) { described_class::WORKER_PICKUP_GRACE }

    it "still considers a sub-grace-period row live even if no lock is held yet" do
      # Simulates the tiny window between orchestrator-seeded
      # record_started! and the worker actually taking its lock.
      make_run("asc", "running", started: 5.seconds.ago)
      aggregator = described_class.new(organization: organization)
      stub_held_locks(aggregator) # no locks held
      payload = aggregator.payload
      expect(payload[:running]).to be true
      expect(payload[:jobs]["asc"][:status]).to eq("running")
    end

    it "flags a post-grace-period row as stranded when its advisory lock is absent" do
      make_run("asc", "running", started: (grace + 1.second).ago)
      aggregator = described_class.new(organization: organization)
      stub_held_locks(aggregator)
      payload = aggregator.payload
      expect(payload[:running]).to be false
      expect(payload[:last_sync_status]).to eq("error")
      expect(payload[:last_sync_error]).to eq(described_class::STALE_ERROR_MESSAGE)
      expect(payload[:jobs]["asc"][:status]).to eq("error")
      expect(payload[:jobs]["asc"][:error_message]).to eq(described_class::STALE_ERROR_MESSAGE)
    end

    it "keeps a post-grace-period row live while its advisory lock is held" do
      # Key property: the time threshold does NOT apply to lock-backed
      # jobs. A legitimately-long 30-minute sync stays "running" forever
      # as long as the lock is held.
      make_run("asc", "running", started: 30.minutes.ago)
      aggregator = described_class.new(organization: organization)
      stub_held_locks(aggregator, :asc)
      payload = aggregator.payload
      expect(payload[:running]).to be true
      expect(payload[:jobs]["asc"][:status]).to eq("running")
    end

    it "falls back to the time-based threshold for jobs without a known lock key" do
      # keywords_popularity has no `with_advisory_lock` guard, so we
      # have no definitive liveness signal for it. Past the 15-minute
      # STALE_RUN_THRESHOLD, treat it as stranded.
      make_run("keywords_popularity", "running",
               started: (described_class::STALE_RUN_THRESHOLD + 1.minute).ago)
      aggregator = described_class.new(organization: organization)
      stub_held_locks(aggregator)
      payload = aggregator.payload
      expect(payload[:running]).to be false
      expect(payload[:jobs]["keywords_popularity"][:status]).to eq("error")
    end

    it "keeps a non-lock-backed job live within the time threshold" do
      make_run("keywords_popularity", "running", started: 5.minutes.ago)
      aggregator = described_class.new(organization: organization)
      stub_held_locks(aggregator)
      payload = aggregator.payload
      expect(payload[:running]).to be true
    end

    it "falls back to the time threshold when the pg_locks probe fails" do
      make_run("asc", "running", started: 5.minutes.ago)
      aggregator = described_class.new(organization: organization)
      allow(aggregator).to receive(:fetch_held_advisory_lock_ids).and_return(nil)
      # Still within 15-minute window → treated as live via time fallback.
      expect(aggregator.payload[:running]).to be true
    end

    it "composes status=partial when one run is stranded and another finished ok" do
      make_run("asc", "running", started: (grace + 1.second).ago)
      make_run("reviews", "ok", finished: 3.minutes.ago)
      aggregator = described_class.new(organization: organization)
      stub_held_locks(aggregator)
      payload = aggregator.payload
      expect(payload[:running]).to be false
      expect(payload[:last_sync_status]).to eq("partial")
    end
  end

  describe "#advisory_lock_key_for" do
    it "maps every lock-backed sync job to its job-side lock key" do
      # If this test fails, the job file changed its with_advisory_lock
      # key and the aggregator drifted — update both in the same commit.
      expect(described_class.advisory_lock_key_for("asc", 42)).to eq("asc:sync:org:42")
      expect(described_class.advisory_lock_key_for("google_play", 42)).to eq("gp:sync:org:42")
      expect(described_class.advisory_lock_key_for("cpp", 42)).to eq("cpp:sync:org:42")
      expect(described_class.advisory_lock_key_for("analytics", 42)).to eq("analytics:sync:org:42")
      expect(described_class.advisory_lock_key_for("reviews", 42)).to eq("reviews:sync:org:42")
      expect(described_class.advisory_lock_key_for("keywords_rank", 42)).to eq("keywords:sync:org:42")
    end

    it "returns nil for jobs that do not guard their body with an advisory lock" do
      expect(described_class.advisory_lock_key_for("keywords_popularity", 42)).to be_nil
    end
  end
end
